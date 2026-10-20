"""Refresh a saved iPhone app while preserving its identity and entitlements."""

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from fnmatch import fnmatchcase
from hashlib import sha1
from pathlib import Path
import plistlib
import json
import re
import shutil
import stat
import subprocess

from iphone_support import InstallCommands, IphoneInstallError


@dataclass(frozen=True)
class IphoneProfile:
    """A decoded provisioning profile and a matching local signing identity."""

    path: Path
    data: dict
    identity: str

    @property
    def expires(self) -> datetime:
        return self.data["ExpirationDate"]


def read_mobileprovision(path: Path) -> dict:
    """Decode a provisioning profile without printing certificates or device identifiers."""
    result = subprocess.run(
        ["security", "cms", "-D", "-i", str(path)], capture_output=True, timeout=20,
    )
    if result.returncode:
        raise IphoneInstallError(f"iPhone provisioning profile cannot be decoded: {path}")
    return plistlib.loads(result.stdout)


def read_app_entitlements(app: Path) -> dict:
    """Read signed entitlements separately from codesign's diagnostic output."""
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True, timeout=20,
    )
    if result.returncode:
        raise IphoneInstallError(f"iPhone app signature cannot be read: {app}")
    return plistlib.loads(result.stdout) if result.stdout.strip() else {}


def entitlement_is_allowed(requested: object, allowed: object) -> bool:
    """Check profile authorization, including wildcard keychain access groups."""
    if isinstance(requested, str) and isinstance(allowed, str):
        return fnmatchcase(requested, allowed)
    if isinstance(requested, list) and isinstance(allowed, list):
        return all(any(entitlement_is_allowed(value, option) for option in allowed) for value in requested)
    if isinstance(requested, dict) and isinstance(allowed, dict):
        return all(key in allowed and entitlement_is_allowed(value, allowed[key]) for key, value in requested.items())
    return type(requested) is type(allowed) and requested == allowed


def validate_app_profile(data: dict, entitlements: dict, bundle_id: str, team_id: str, udid: str) -> None:
    """Require the same app identity, team, device and every existing entitlement."""
    if team_id not in data.get("TeamIdentifier", []):
        raise IphoneInstallError("iPhone profile belongs to a different development team.")
    if udid not in data.get("ProvisionedDevices", []):
        raise IphoneInstallError("iPhone profile does not include the selected phone. Register it in Xcode first.")
    identifier = entitlements.get("application-identifier", "")
    prefixes = data.get("ApplicationIdentifierPrefix", [])
    if identifier not in [f"{prefix}.{bundle_id}" for prefix in prefixes]:
        raise IphoneInstallError("iPhone app identity differs from the profile; refusing to change app storage access.")
    allowed = data.get("Entitlements", {})
    for key, value in entitlements.items():
        if key not in allowed or not entitlement_is_allowed(value, allowed[key]):
            raise IphoneInstallError(f"iPhone profile does not authorize the existing entitlement: {key}")


def find_iphone_profile(bundle_id: str, team_id: str, udid: str, entitlements: dict) -> IphoneProfile | None:
    """Choose the longest-lived compatible profile with a valid private key in Keychain."""
    identities = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True, check=True, timeout=20,
    ).stdout.decode()
    valid_identities = set(re.findall(r"\b[0-9A-F]{40}\b", identities))
    directories = [
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
    ]
    matches = []
    for directory in directories:
        for path in directory.glob("*.mobileprovision"):
            try:
                data = read_mobileprovision(path)
                validate_app_profile(data, entitlements, bundle_id, team_id, udid)
                if data["ExpirationDate"] <= datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=2):
                    continue
                certificates = {sha1(cert).hexdigest().upper() for cert in data["DeveloperCertificates"]}
                matching = certificates & valid_identities
                if matching:
                    matches.append(IphoneProfile(path, data, sorted(matching)[0]))
            except (IphoneInstallError, KeyError, ValueError, plistlib.InvalidFileException):
                continue
    return max(matches, key=lambda profile: profile.expires, default=None)


def renew_iphone_profile(
    commands: InstallCommands, state: Path, bundle_id: str, team_id: str,
    udid: str, entitlements: dict,
) -> IphoneProfile:
    """Bypass this app's cached profiles and require a later expiry; restore backups on failure."""
    previous = find_iphone_profile(bundle_id, team_id, udid, entitlements)
    directories = [
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
    ]
    backups = []
    backup_directory = commands.log.parent / "profile-backups"
    backup_directory.mkdir(exist_ok=True)
    for directory in directories:
        for path in directory.glob("*.mobileprovision"):
            if path.is_symlink():
                continue
            try:
                data = read_mobileprovision(path)
            except (IphoneInstallError, ValueError, plistlib.InvalidFileException):
                continue
            app_id = data.get("Entitlements", {}).get("application-identifier")
            prefixes = data.get("ApplicationIdentifierPrefix", [])
            if team_id not in data.get("TeamIdentifier", []) or app_id not in {f"{prefix}.{bundle_id}" for prefix in prefixes}:
                continue
            backup = backup_directory / f"{len(backups)}.mobileprovision"
            shutil.copyfile(path, backup)
            backups.append((path, backup))
    (backup_directory / "manifest.json").write_text(json.dumps([
        {"original": str(path), "backup": str(backup)} for path, backup in backups
    ], indent=2) + "\n")
    print("Requesting fresh provisioning from Xcode; cached app profiles are backed up…", flush=True)
    succeeded = False
    try:
        for path, _ in backups:
            path.unlink()
        profile = ensure_iphone_profile(commands, state, bundle_id, team_id, udid, entitlements, request_update=True)
        if previous is not None and profile.expires <= previous.expires:
            raise IphoneInstallError(
                "iPhone profile renewal did not extend its expiration "
                f"({previous.expires:%Y-%m-%d %H:%M} UTC). Xcode returned an existing or shorter-lived profile. "
                "Cached profiles were restored; the installed app was not changed. "
                "Retry after expiry, or run without --renew-profile to re-sign with the current profile."
            )
        print(f"Provisioning expires {profile.expires:%Y-%m-%d %H:%M} UTC.", flush=True)
        succeeded = True
        return profile
    finally:
        for path, backup in backups:
            if not succeeded or not path.exists():
                shutil.copyfile(backup, path)


def ensure_iphone_profile(
    commands: InstallCommands, state: Path, bundle_id: str, team_id: str,
    udid: str, entitlements: dict, *, request_update: bool = False,
) -> IphoneProfile:
    """Request Xcode automatic signing when provisioning is missing or explicitly refreshed."""
    profile = find_iphone_profile(bundle_id, team_id, udid, entitlements)
    if profile is None or request_update:
        print("Renewing the iPhone signing profile…", flush=True)
        helper = state / "profile-helper"
        project = helper / "ProfileMint.xcodeproj"
        project.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(Path(__file__).with_name("profile-project.pbxproj"), project / "project.pbxproj")
        (helper / "main.m").write_text("int main(int argc, char *argv[]) { return 0; }\n")
        managed = {"application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups", "get-task-allow"}
        (helper / "ProfileMint.entitlements").write_bytes(plistlib.dumps({
            key: value for key, value in entitlements.items() if key not in managed
        }))
        commands.run([
            "xcodebuild", "-project", str(project), "-scheme", "ProfileMint",
            "-configuration", "Debug", "-destination", "generic/platform=iOS",
            "-derivedDataPath", str(helper / "DerivedData"), "-allowProvisioningUpdates",
            f"DEVELOPMENT_TEAM={team_id}", f"PRODUCT_BUNDLE_IDENTIFIER={bundle_id}", "build",
        ], timeout=300)
        profile = find_iphone_profile(bundle_id, team_id, udid, entitlements)
    if profile is None:
        raise IphoneInstallError(
            "iPhone signing profile is missing or incompatible. Check the Apple account in Xcode Settings, "
            "the local configuration's team_id, and this phone's registration."
        )
    destination = Path.home() / "Library/MobileDevice/Provisioning Profiles" / profile.path.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    if profile.path != destination:
        shutil.copyfile(profile.path, destination)
    return profile


def validate_refresh_bundle(app: Path, bundle_id: str, team_id: str) -> dict:
    """Accept this workflow's device app with frameworks but no separately provisioned extensions."""
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != bundle_id:
        raise IphoneInstallError(f"iPhone bundle identifier does not match local configuration: {app}")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise IphoneInstallError("iPhone refresh requires a device build, not a simulator build.")
    if any(app.rglob("*.appex")) or any(app.rglob("*.app")):
        raise IphoneInstallError("iPhone refresh does not support embedded apps or extensions. Use --build for the local development configuration.")
    data = read_mobileprovision(app / "embedded.mobileprovision")
    if team_id not in data.get("TeamIdentifier", []):
        raise IphoneInstallError("iPhone saved app belongs to a different team. Refusing to change its identity.")
    return read_app_entitlements(app)


def resign_iphone_app(commands: InstallCommands, source: Path, destination: Path, profile: IphoneProfile) -> None:
    """Sign a private copy from the innermost framework outward, preserving signed entitlements."""
    commands.run(["ditto", str(source), str(destination)])
    for path in [destination, *destination.rglob("*")]:
        if not path.is_symlink():
            path.chmod(path.stat().st_mode | stat.S_IWUSR)
    shutil.copyfile(profile.path, destination / "embedded.mobileprovision")
    nested = [path for path in destination.rglob("*") if path.suffix in (".framework", ".dylib") and not path.is_symlink()]
    for index, path in enumerate([*sorted(nested, key=lambda p: len(p.parts), reverse=True), destination]):
        entitlements = read_app_entitlements(path)
        arguments = ["codesign", "--force", "--sign", profile.identity, "--preserve-metadata=identifier,flags"]
        if entitlements:
            entitlement_path = commands.log.parent / f"signing-{index}.plist"
            entitlement_path.write_bytes(plistlib.dumps(entitlements))
            arguments += ["--entitlements", str(entitlement_path), "--generate-entitlement-der"]
        commands.run(arguments + [str(path)])
    commands.run(["codesign", "--verify", "--deep", "--strict", str(destination)])
    if read_app_entitlements(source) != read_app_entitlements(destination):
        raise IphoneInstallError("iPhone refreshed entitlements changed unexpectedly; installation stopped.")
