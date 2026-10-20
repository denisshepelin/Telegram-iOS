"""Regression tests for device selection and preservation of iPhone signing identity."""

import argparse
from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
from hashlib import sha1
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from install_iphone import run_iphone_install, select_iphone_device, update_telegram_sources
from iphone_signing import IphoneProfile, entitlement_is_allowed, find_iphone_profile, validate_app_profile
from iphone_support import InstallCommands, IphoneInstallError


def profile_fixture() -> dict:
    return {
        "TeamIdentifier": ["TEAM123456"], "ApplicationIdentifierPrefix": ["PREFIX1234"],
        "ProvisionedDevices": ["phone-1"], "DeveloperCertificates": [b"certificate"],
        "ExpirationDate": datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=7),
        "Entitlements": {
            "application-identifier": "PREFIX1234.org.example.telegram",
            "com.apple.security.application-groups": ["group.org.example.telegram"],
            "keychain-access-groups": ["PREFIX1234.*"], "get-task-allow": True,
        },
    }


def phone_fixture(identifier: str, state: str = "connected") -> dict:
    return {
        "identifier": identifier,
        "hardwareProperties": {"udid": identifier, "deviceType": "iPhone"},
        "deviceProperties": {"name": identifier, "developerModeStatus": "enabled"},
        "connectionProperties": {"tunnelState": state, "pairingState": "paired"},
    }


class IphoneSigningTests(unittest.TestCase):
    def setUp(self):
        self.profile = profile_fixture()
        self.entitlements = dict(self.profile["Entitlements"], **{"keychain-access-groups": ["PREFIX1234.org.example.telegram"]})

    def validate(self):
        validate_app_profile(self.profile, self.entitlements, "org.example.telegram", "TEAM123456", "phone-1")

    def test_app_prefix_need_not_equal_team_identifier(self):
        self.validate()

    def test_rejects_different_team_device_or_app_identity(self):
        for key, value in (("TeamIdentifier", ["OTHER12345"]), ("ProvisionedDevices", ["phone-2"]), ("ApplicationIdentifierPrefix", ["OTHER12345"])):
            with self.subTest(key=key):
                self.profile = dict(profile_fixture(), **{key: value})
                with self.assertRaises(IphoneInstallError):
                    self.validate()

    def test_cannot_drop_app_group_to_fit_profile(self):
        self.profile["Entitlements"]["com.apple.security.application-groups"] = []
        with self.assertRaisesRegex(IphoneInstallError, "existing entitlement"):
            self.validate()

    def test_keychain_wildcard_cannot_authorize_another_prefix(self):
        self.assertTrue(entitlement_is_allowed(["PREFIX1234.app"], ["PREFIX1234.*"]))
        self.assertFalse(entitlement_is_allowed(["OTHER12345.app"], ["PREFIX1234.*"]))
        self.assertFalse(entitlement_is_allowed(True, 1))

    def test_expired_and_wrong_certificate_profiles_are_skipped(self):
        fingerprint = sha1(b"certificate").hexdigest().upper()
        identity_output = subprocess.CompletedProcess([], 0, f'1) {fingerprint} "Apple Development"'.encode())
        profiles = {
            "expired": dict(self.profile, ExpirationDate=datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(hours=1)),
            "wrong-key": dict(self.profile, DeveloperCertificates=[b"another certificate"]),
            "valid": self.profile,
        }
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            folder = home / "Library/MobileDevice/Provisioning Profiles"
            folder.mkdir(parents=True)
            for name in profiles:
                (folder / f"{name}.mobileprovision").touch()
            with patch("iphone_signing.Path.home", return_value=home), patch("iphone_signing.subprocess.run", return_value=identity_output), patch("iphone_signing.read_mobileprovision", side_effect=lambda p: profiles[p.stem]):
                result = find_iphone_profile("org.example.telegram", "TEAM123456", "phone-1", self.entitlements)
            self.assertEqual(result.path.stem, "valid")
            self.assertEqual(result.identity, fingerprint)


class IphoneDeviceTests(unittest.TestCase):
    def test_auto_selects_only_reachable_phone(self):
        selected = select_iphone_device([phone_fixture("mine"), phone_fixture("other", "unavailable")], None, None)
        self.assertEqual(selected["identifier"], "mine")

    def test_does_not_fall_back_when_remembered_phone_is_offline(self):
        with self.assertRaisesRegex(IphoneInstallError, "unavailable"):
            select_iphone_device([phone_fixture("mine", "unavailable"), phone_fixture("other")], None, "mine")

    def test_multiple_phones_require_selection(self):
        with self.assertRaisesRegex(IphoneInstallError, "ambiguous"):
            select_iphone_device([phone_fixture("mine"), phone_fixture("other")], None, None)

    def test_explicit_phone_overrides_remembered_phone(self):
        selected = select_iphone_device([phone_fixture("mine"), phone_fixture("other")], "other", "mine")
        self.assertEqual(selected["identifier"], "other")


class IphoneGitUpdateTests(unittest.TestCase):
    def test_rebase_preserves_local_commits_and_uncommitted_edits(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            remote, work, upstream = root / "remote", root / "work", root / "upstream"

            def git(directory, *args):
                return subprocess.run(["git", "-C", str(directory), *args], check=True, capture_output=True).stdout

            remote.mkdir()
            git(remote, "init", "--bare", "--initial-branch=master")
            git(root, "clone", str(remote), str(work))
            for directory in (work,):
                git(directory, "config", "user.name", "Install Test")
                git(directory, "config", "user.email", "install@example.invalid")
            (work / "initial").write_text("base\n")
            git(work, "add", ".")
            git(work, "commit", "-m", "base")
            git(work, "push", "-u", "origin", "master")
            git(root, "clone", str(remote), str(upstream))
            git(upstream, "config", "user.name", "Install Test")
            git(upstream, "config", "user.email", "install@example.invalid")
            (upstream / "incoming").write_text("upstream\n")
            git(upstream, "add", ".")
            git(upstream, "commit", "-m", "upstream change")
            git(upstream, "push")
            (work / "local").write_text("local commit\n")
            git(work, "add", ".")
            git(work, "commit", "-m", "local change")
            (work / "initial").write_text("uncommitted work\n")
            update_telegram_sources(InstallCommands(work, root / "commands.log"))
            self.assertEqual((work / "initial").read_text(), "uncommitted work\n")
            self.assertEqual((work / "local").read_text(), "local commit\n")
            self.assertEqual((work / "incoming").read_text(), "upstream\n")
            self.assertEqual(git(work, "rev-list", "--count", "HEAD..origin/master").strip(), b"0")
            self.assertEqual(git(work, "rev-list", "--count", "origin/master..HEAD").strip(), b"1")


class IphoneRefreshWorkflowTests(unittest.TestCase):
    def check_saved_refresh(self, reject_launch: bool):
        with tempfile.TemporaryDirectory() as temporary, ExitStack() as patches:
            root = Path(temporary)
            source = root / "source/Telegram.app"
            source.mkdir(parents=True)
            (source / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0", "CFBundleVersion": "42"}))
            profile_data = profile_fixture()
            profile = IphoneProfile(root / "profile", profile_data, "certificate")
            patches.enter_context(patch("install_iphone.INSTALL_STATE", root))
            patches.enter_context(patch("install_iphone.find_saved_iphone_app", return_value=source))
            patches.enter_context(patch("install_iphone.validate_refresh_bundle", return_value=profile_data["Entitlements"]))
            patches.enter_context(patch("install_iphone.ensure_iphone_profile", return_value=profile))
            patches.enter_context(patch("install_iphone.resign_iphone_app", side_effect=lambda commands, src, dst, profile: shutil.copytree(src, dst)))
            patches.enter_context(patch("install_iphone.build_telegram_iphone", side_effect=AssertionError("refresh must not compile")))
            patches.enter_context(patch("install_iphone.update_telegram_sources", side_effect=AssertionError("refresh must not fetch")))
            operations = []

            class DeviceCommands:
                log = root / "logs/run/commands.log"

                def json(self, args, name, timeout):
                    operations.append(name)
                    if name == "devices":
                        return {"devices": [phone_fixture("phone-1")]}
                    if name == "installed-app":
                        return {"apps": [{"bundleIdentifier": "org.example.telegram", "bundleVersion": "42"}]}
                    if name == "launch" and reject_launch:
                        raise IphoneInstallError("Device rejected launch")
                    return {}

            args = argparse.Namespace(device=None, app=None, update=False, build=False, no_launch=False, renew_profile=False)
            config = {"bundle_id": "org.example.telegram", "team_id": "TEAM123456"}
            if reject_launch:
                with self.assertRaisesRegex(IphoneInstallError, "installed, but its launch failed"):
                    run_iphone_install(args, config, {}, DeviceCommands())
            else:
                run_iphone_install(args, config, {}, DeviceCommands())
            saved = json.loads((root / "current.json").read_text())
            self.assertTrue((root / saved["app"] / "Info.plist").exists())
            self.assertEqual(saved["device"], "phone-1")
            self.assertEqual(operations, ["devices", "install", "installed-app", "launch"])

    def test_saved_refresh_installs_and_launches_without_build_or_fetch(self):
        self.check_saved_refresh(reject_launch=False)

    def test_launch_failure_is_reported_and_signed_artifact_is_retained(self):
        self.check_saved_refresh(reject_launch=True)


if __name__ == "__main__":
    unittest.main()
