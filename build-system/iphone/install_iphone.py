# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""One-command local iPhone refresh, build and installation for Telegram."""

import argparse
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
from uuid import uuid4

from iphone_signing import (
    ensure_iphone_profile, renew_iphone_profile, read_mobileprovision, resign_iphone_app,
    validate_app_profile, validate_refresh_bundle,
)
from iphone_support import InstallCommands, IphoneInstallError, write_install_state


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
INSTALL_STATE = REPOSITORY_ROOT / "build/iphone-install"
DERIVED_DATA = REPOSITORY_ROOT / "build/XcodeDerivedData"


def select_iphone_device(devices: list[dict], requested: str | None, remembered: str | None) -> dict:
    """Never switch from a remembered iPhone to somebody else's connected phone."""
    phones = [device for device in devices if device.get("hardwareProperties", {}).get("deviceType") == "iPhone"]
    selection = requested or remembered
    if selection:
        matches = [device for device in phones if selection in (
            device["identifier"], device["hardwareProperties"].get("udid"), device["deviceProperties"].get("name"),
        )]
    else:
        matches = [device for device in phones if device.get("connectionProperties", {}).get("tunnelState") in ("connected", "connecting", "disconnected")]
    if len(matches) != 1:
        available = ", ".join(device["deviceProperties"]["name"] for device in phones) or "none"
        raise IphoneInstallError(f"iPhone selection is unavailable or ambiguous. Use --device NAME or UDID. Known phones: {available}")
    device = matches[0]
    if device.get("connectionProperties", {}).get("pairingState") != "paired":
        raise IphoneInstallError("iPhone is not paired. Connect by USB and trust this Mac on the phone.")
    if device["deviceProperties"].get("developerModeStatus") != "enabled":
        raise IphoneInstallError("iPhone Developer Mode is disabled. Enable it in Settings > Privacy & Security.")
    if device.get("connectionProperties", {}).get("tunnelState") == "unavailable":
        raise IphoneInstallError("iPhone is unavailable. Connect and unlock the selected phone, then run again.")
    return device


def find_saved_iphone_app(state: dict, explicit: Path | None, bundle_id: str) -> Path | None:
    """Prefer the saved artifact; import only an unambiguous existing device build."""
    if explicit:
        app = explicit.expanduser().resolve()
        if not (app / "Info.plist").is_file():
            raise IphoneInstallError(f"iPhone app is missing Info.plist: {app}")
        return app
    if state.get("app"):
        app = INSTALL_STATE / state["app"]
        if (app / "Info.plist").is_file():
            return app
    candidates = []
    for app in (DERIVED_DATA / "Build/Products/Debug-iphoneos").glob("bazel-out/*/bin/Telegram/Telegram.app"):
        if plistlib.loads((app / "Info.plist").read_bytes()).get("CFBundleIdentifier") == bundle_id:
            candidates.append(app)
    if len(candidates) > 1:
        raise IphoneInstallError("iPhone build discovery found multiple apps. Select the intended build with --app PATH.")
    return candidates[0] if candidates else None


def update_telegram_sources(commands: InstallCommands) -> None:
    """Fetch the configured upstream and preserve tracked local edits through Git's autostash."""
    branch = commands.run(["git", "symbolic-ref", "--quiet", "--short", "HEAD"]).decode().strip()
    upstream = commands.run(["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]).decode().strip()
    remote = commands.run(["git", "config", "--get", f"branch.{branch}.remote"]).decode().strip()
    print(f"Fetching {upstream}…", flush=True)
    commands.run(["git", "fetch", "--", remote], timeout=300)
    behind = int(commands.run(["git", "rev-list", "--count", f"HEAD..{upstream}"]).decode().strip())
    if behind:
        print(f"Rebasing {branch} onto {upstream} ({behind} incoming commits)…", flush=True)
        try:
            commands.run(["git", "rebase", "--autostash", upstream], timeout=300)
        except IphoneInstallError as error:
            raise IphoneInstallError(
                "iPhone source update stopped during rebase. Run git status, resolve conflicts and git rebase --continue "
                "(or git rebase --abort), then rerun --update. " + str(error)
            ) from error
        if commands.run(["git", "diff", "--name-only", "--diff-filter=U"]).strip():
            raise IphoneInstallError("iPhone source update has conflicts while restoring local edits. Resolve them before building.")
    else:
        print("Upstream has no new commits.", flush=True)


def build_telegram_iphone(commands: InstallCommands, configuration: Path, disable_ads: bool = False) -> Path:
    """Regenerate through Make.py and build for generic iOS with the existing Bazel cache."""
    if commands.run(["git", "ls-files", "--unmerged"]).strip():
        raise IphoneInstallError("iPhone build has unresolved Git conflicts. Resolve them before building.")
    print("Synchronizing submodules…", flush=True)
    commands.run(["git", "submodule", "update", "--init", "--recursive"], timeout=900)
    version = commands.run(["xcodebuild", "-version"]).decode().splitlines()[0].removeprefix("Xcode ")
    pinned = json.loads((REPOSITORY_ROOT / "versions.json").read_text())["xcode"]
    make = ["uv", "run", "build-system/Make/Make.py"]
    if version != pinned:
        print(f"Using installed Xcode {version} (repository specifies {pinned}).", flush=True)
        make += ["--overrideXcodeVersion"]
    print("Generating the device project…", flush=True)
    commands.run(make + [
        f"--cacheDir={Path.home() / 'telegram-bazel-cache'}", "generateProject",
        "--configurationPath", str(configuration), "--xcodeManagedCodesigning",
        "--target", "Telegram", "--noOpenXcode",
    ] + (["--disable-ads"] if disable_ads else []), timeout=1800)
    print("Building Telegram for iPhone…", flush=True)
    commands.run([
        "xcodebuild", "-project", "Telegram/Telegram.xcodeproj", "-scheme", "Telegram",
        "-configuration", "Debug", "-destination", "generic/platform=iOS",
        "-derivedDataPath", str(DERIVED_DATA), "-allowProvisioningUpdates", "build",
    ], timeout=7200)
    settings = commands.run([
        "xcodebuild", "-project", "Telegram/Telegram.xcodeproj", "-scheme", "Telegram",
        "-configuration", "Debug", "-destination", "generic/platform=iOS",
        "-derivedDataPath", str(DERIVED_DATA), "-showBuildSettings", "-json",
    ])
    # Xcode can print diagnostics before its JSON build settings.
    start = settings.find(b"[\n")
    if start == -1:
        raise IphoneInstallError("iPhone build settings did not contain JSON. See the run log.")
    for target in json.loads(settings[start:]):
        values = target.get("buildSettings", {})
        if target.get("target") == "Telegram":
            app = Path(values["TARGET_BUILD_DIR"]) / values["FULL_PRODUCT_NAME"]
            if (app / "Info.plist").is_file():
                return app
    raise IphoneInstallError("iPhone build succeeded but its Telegram.app could not be located from Xcode build settings.")


def iphone_install_arguments() -> argparse.Namespace:
    """Parse the small installation interface; refresh is the default action."""
    parser = argparse.ArgumentParser(
        prog="./install-iphone",
        description="Refresh and install the saved Telegram build without opening Xcode.",
        epilog="Examples: ./install-iphone | ./install-iphone --build | ./install-iphone --update\n"
               "See build-system/iphone/README.md. No prompts; Apple login and device trust are one-time setup.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        allow_abbrev=False,
    )
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--build", action="store_true", help="build local source and install; do not fetch upstream")
    action.add_argument("--update", action="store_true", help="fetch upstream, rebase if behind, build and install")
    action.add_argument("--status", action="store_true", help="show saved app, phone and signing expiry without changes")
    parser.add_argument("--disable-ads", action="store_true", help="with --build or --update, receive ads without rendering them")
    parser.add_argument("--renew-profile", action="store_true", help="bypass cached app profiles and ask Xcode for a later expiry; fail if expiry does not advance")
    parser.add_argument("--device", help="iPhone name, UDID or CoreDevice identifier; successful choice is remembered")
    parser.add_argument("--app", type=Path, help="refresh an existing Telegram.app instead of the saved artifact")
    parser.add_argument("--configuration", type=Path, default=REPOSITORY_ROOT / "build-system/local-development.json", help="local build configuration JSON")
    parser.add_argument("--dry-run", action="store_true", help="describe the operation without fetching, signing, building or installing")
    parser.add_argument("--verbose", action="store_true", help="print command lines as well as progress and log locations")
    parser.add_argument("--no-launch", action="store_true", help="install and verify bundle metadata without opening the app")
    if "--help" in sys.argv or "-h" in sys.argv:
        parser.print_help()
        parser.exit()
    args = parser.parse_args()
    if args.app and (args.build or args.update):
        parser.error("--app cannot be combined with --build or --update")
    if args.disable_ads and not (args.build or args.update):
        parser.error("--disable-ads requires --build or --update")
    if args.renew_profile and args.status:
        parser.error("--renew-profile cannot be combined with --status")
    return args


def run_iphone_install(args: argparse.Namespace, config: dict, state: dict, commands: InstallCommands) -> None:
    """Prepare and verify an artifact before replacing the installation on the selected iPhone."""
    devices = commands.json(["xcrun", "devicectl", "list", "devices"], "devices", timeout=30)["devices"]
    device = select_iphone_device(devices, args.device, state.get("device"))
    udid = device["hardwareProperties"]["udid"]
    name = device["deviceProperties"]["name"]
    bundle_id, team_id = config["bundle_id"], config["team_id"]
    print(f"Using {name}.", flush=True)
    source = find_saved_iphone_app(state, args.app, bundle_id)
    entitlements = validate_refresh_bundle(source, bundle_id, team_id) if source and not (args.build or args.update) else {
        "application-identifier": f"{team_id}.{bundle_id}",
        "com.apple.security.application-groups": [f"group.{bundle_id}"],
        "get-task-allow": True,
    }
    if args.update:
        update_telegram_sources(commands)
    profile_function = renew_iphone_profile if args.renew_profile else ensure_iphone_profile
    profile = profile_function(commands, INSTALL_STATE, bundle_id, team_id, udid, entitlements)
    built = args.build or args.update or source is None
    if built:
        source = build_telegram_iphone(commands, args.configuration.resolve(), disable_ads=args.disable_ads)
        entitlements = validate_refresh_bundle(source, bundle_id, team_id)
        profile = ensure_iphone_profile(commands, INSTALL_STATE, bundle_id, team_id, udid, entitlements)
    validate_app_profile(profile.data, entitlements, bundle_id, team_id, udid)
    artifact = INSTALL_STATE / "artifacts" / commands.log.parent.name / "Telegram.app"
    artifact.parent.mkdir(parents=True)
    print("Refreshing the saved app signature…", flush=True)
    resign_iphone_app(commands, source, artifact, profile)
    info = plistlib.loads((artifact / "Info.plist").read_bytes())
    saved = {
        "app": str(artifact.relative_to(INSTALL_STATE)), "bundle_id": bundle_id,
        "expires": profile.expires.isoformat() + "Z", "version": info["CFBundleShortVersionString"],
        "build": str(info["CFBundleVersion"]), "device": state.get("device"),
        "device_name": state.get("device_name"),
    }
    write_install_state(INSTALL_STATE / "current.json", saved)
    print(f"Installing on {name}…", flush=True)
    commands.json([
        "xcrun", "devicectl", "device", "install", "app", "--device", udid, str(artifact),
    ], "install", timeout=180)
    installed = commands.json([
        "xcrun", "devicectl", "device", "info", "apps", "--device", udid, "--bundle-id", bundle_id,
    ], "installed-app", timeout=30)["apps"]
    if not any(app.get("bundleIdentifier") == bundle_id and app.get("bundleVersion") == saved["build"] for app in installed):
        raise IphoneInstallError("iPhone installation could not be verified. The signed artifact is saved; run again to retry.")
    saved.update(device=udid, device_name=name)
    write_install_state(INSTALL_STATE / "current.json", saved)
    if not args.no_launch:
        print("Checking that the app launches…", flush=True)
        try:
            commands.json([
                "xcrun", "devicectl", "device", "process", "launch", "--device", udid, bundle_id,
            ], "launch", timeout=30)
        except IphoneInstallError as error:
            raise IphoneInstallError(
                "iPhone app was installed, but its launch failed. Unlock the phone. For a signature/trust rejection, "
                "check Settings > General > VPN & Device Management and trust/verify the developer while online. "
                "The signed app is saved; rerun this command after resolving the device error. " + str(error)
            ) from error
    retained = {artifact.parent.name}
    if state.get("app"):
        retained.add(Path(state["app"]).parent.name)
    for directory in (INSTALL_STATE / "artifacts").iterdir():
        if directory.name not in retained and re.fullmatch(r"\d{8}-\d{6}-[0-9a-f]{8}", directory.name) and directory.is_dir() and not directory.is_symlink():
            shutil.rmtree(directory)
    print(f"Installed {info.get('CFBundleDisplayName', 'Telegram')} {saved['version']} on {name}. "
          f"Signing expires {profile.expires:%Y-%m-%d %H:%M} UTC.")
    if not built:
        print("Used the saved build; no compilation or source updates.")


def iphone_install_main() -> int:
    """Validate local setup before creating private installation state or running external commands."""
    args = iphone_install_arguments()
    try:
        args.configuration = args.configuration.expanduser().resolve()
        config = json.loads(args.configuration.read_text())
        if not re.fullmatch(r"[A-Za-z0-9.-]+", config.get("bundle_id", "")) or not re.fullmatch(r"[A-Z0-9]{10}", config.get("team_id", "")):
            raise IphoneInstallError("iPhone configuration requires a valid bundle_id and ten-character team_id.")
        state_file = INSTALL_STATE / "current.json"
        state = json.loads(state_file.read_text()) if state_file.exists() else {}
        if args.dry_run or args.status:
            app = find_saved_iphone_app(state, args.app, config["bundle_id"])
            print(f"App: {app or 'none; the first run will build local source'}")
            print(f"Phone: {args.device or state.get('device_name') or 'the only reachable paired iPhone'}")
            if app:
                print(f"Signing expires: {read_mobileprovision(app / 'embedded.mobileprovision')['ExpirationDate']} UTC")
            if args.dry_run:
                if args.renew_profile:
                    print("Back up only this app and team’s cached profiles; request provisioning through Xcode; require a later expiry before installation.")
                if args.update:
                    print("Fetch configured upstream and rebase with autostash only if behind; stop on conflicts.")
                if args.build or args.update or not app:
                    print("Synchronize submodules, regenerate without opening Xcode, and build for generic iOS.")
                print("Find or renew compatible signing; sign a private app copy; install and verify on the selected phone.")
                if not args.no_launch:
                    print("Launch the app to check device trust and signing.")
            return 0
        for executable in ("uv", "xcodebuild", "xcrun", "security", "codesign", "ditto", "git"):
            if shutil.which(executable) is None:
                raise IphoneInstallError(f"iPhone prerequisite is missing: {executable}")
        os.umask(0o077)
        INSTALL_STATE.mkdir(parents=True, exist_ok=True)
        with (INSTALL_STATE / "install.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise IphoneInstallError("iPhone installation is already running for this checkout.") from error
            run = INSTALL_STATE / "logs" / (datetime.now().strftime("%Y%m%d-%H%M%S-") + uuid4().hex[:8])
            run.mkdir(parents=True)
            commands = InstallCommands(REPOSITORY_ROOT, run / "commands.log", args.verbose)
            print(f"Installation log: {commands.log}", flush=True)
            state = json.loads(state_file.read_text()) if state_file.exists() else {}
            run_iphone_install(args, config, state, commands)
        return 0
    except KeyboardInterrupt:
        print("iPhone installation interrupted. Run again to retry.", file=sys.stderr)
        return 130
    except (IphoneInstallError, OSError, ValueError, KeyError, subprocess.SubprocessError, plistlib.InvalidFileException) as error:
        print(f"iPhone installation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(iphone_install_main())
