"""Profile renewal must preserve working signing and distinguish renewal from re-download."""

from datetime import timedelta
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from install_iphone import iphone_install_arguments
from iphone_signing import IphoneProfile, renew_iphone_profile
from iphone_support import InstallCommands, IphoneInstallError
from test_iphone_install import profile_fixture


class IphoneProfileRenewalTests(unittest.TestCase):
    def check_renewal(self, outcome):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = root / "Library/Developer/Xcode/UserData/Provisioning Profiles"
            cache.mkdir(parents=True)
            original = cache / "telegram.mobileprovision"
            original.write_bytes(b"original")
            unrelated = cache / "other.mobileprovision"
            unrelated.write_bytes(b"other")
            logs = root / "logs"
            logs.mkdir()
            data = profile_fixture()
            previous = IphoneProfile(original, data, "identity")
            replacement = dict(data, ExpirationDate=data["ExpirationDate"] + timedelta(days=1) if outcome == "renewed" else data["ExpirationDate"])

            def request_profile(*args, **kwargs):
                self.assertTrue(kwargs["request_update"])
                self.assertFalse(original.exists())
                self.assertEqual(unrelated.read_bytes(), b"other")
                original.write_bytes(b"downloaded")
                if outcome == "failure":
                    raise IphoneInstallError("offline")
                if outcome == "interrupted":
                    raise KeyboardInterrupt()
                return IphoneProfile(original, replacement, "identity")

            def read_profile(path):
                if path == unrelated:
                    return dict(data, Entitlements={"application-identifier": "PREFIX1234.org.other.app"})
                return data

            with patch("iphone_signing.Path.home", return_value=root), patch("iphone_signing.find_iphone_profile", return_value=previous), patch("iphone_signing.read_mobileprovision", side_effect=read_profile), patch("iphone_signing.ensure_iphone_profile", side_effect=request_profile):
                arguments = (InstallCommands(root, logs / "commands.log"), root, "org.example.telegram", "TEAM123456", "phone-1", data["Entitlements"])
                if outcome == "renewed":
                    result = renew_iphone_profile(*arguments)
                    self.assertGreater(result.expires, previous.expires)
                elif outcome == "interrupted":
                    with self.assertRaises(KeyboardInterrupt):
                        renew_iphone_profile(*arguments)
                else:
                    with self.assertRaisesRegex(IphoneInstallError, "offline" if outcome == "failure" else "did not extend"):
                        renew_iphone_profile(*arguments)
            self.assertEqual(original.read_bytes(), b"downloaded" if outcome == "renewed" else b"original")
            self.assertEqual(unrelated.read_bytes(), b"other")
            self.assertEqual((logs / "profile-backups/0.mobileprovision").read_bytes(), b"original")
            self.assertTrue((logs / "profile-backups/manifest.json").exists())

    def test_new_expiry_is_accepted(self):
        self.check_renewal("renewed")

    def test_unchanged_expiry_is_rejected_and_original_restored(self):
        self.check_renewal("unchanged")

    def test_network_failure_restores_original(self):
        self.check_renewal("failure")

    def test_ctrl_c_restores_original(self):
        self.check_renewal("interrupted")

    def test_cli_accepts_renewal_with_build_and_dry_run(self):
        with patch("sys.argv", ["install-iphone", "--renew-profile", "--build", "--dry-run"]):
            args = iphone_install_arguments()
        self.assertTrue(args.renew_profile and args.build and args.dry_run)

    def test_cli_rejects_renewal_with_status(self):
        with patch("sys.argv", ["install-iphone", "--renew-profile", "--status"]), self.assertRaises(SystemExit) as error:
            iphone_install_arguments()
        self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
