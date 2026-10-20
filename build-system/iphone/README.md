# Install Telegram on your iPhone

From the repository root:

```sh
./install-iphone
```

This refreshes the saved app's signature, installs it, and checks that it launches.
It does not fetch source, compile Telegram, or open Xcode. On the first run it
imports the existing device build under `build/XcodeDerivedData`; if none exists,
it builds the local source once. Local edits are included only when you build.

```sh
./install-iphone --build       # Build local changes and install
./install-iphone --build --disable-ads --renew-profile # Build without ad rendering and refresh signing
./install-iphone --update      # Fetch upstream, rebase if behind, build and install
./install-iphone --status      # Show saved app, selected phone and signing expiry
./install-iphone --renew-profile # Request a later profile expiry, then re-sign and install
./install-iphone --dry-run     # Preview without changing anything
```

All commands work from fish, zsh or bash. The launcher uses `uv` and Python's
standard library; no additional Python packages are needed.

## First-time setup

- Install Xcode and select it as the active developer directory. The standalone
  Command Line Tools package is insufficient. Sign in to your Apple account in
  Xcode Settings once; routine installs keep Xcode closed.
- Keep your existing `build-system/local-development.json`, including your own
  Telegram API credentials, `bundle_id`, and `team_id`. The team must match the
  signing certificate and provisioning profile. Do not commit private credentials.
- Pair the iPhone with this Mac, trust the Mac, and enable Developer Mode. Connect
  and unlock it for installation. A previously paired, reachable wireless device
  also works; USB is the easiest way to recover a missing connection.
- If iOS requests developer trust, open Settings > General > VPN & Device
  Management and trust/verify the developer while connected to the internet.

The only reachable paired iPhone is selected on the first run. Its UDID is
remembered after installation. An unavailable remembered phone never causes an
automatic switch to someone else's phone. Override the selection explicitly:

```sh
./install-iphone --device "My iPhone"
./install-iphone --device "<device-udid>"
```

## Signing and saved builds

The installer chooses an unexpired profile that permits this phone, development
team, app identity and every existing entitlement, with a matching private key in
the login Keychain. It renews missing or expired provisioning by building a tiny
permanent helper with Xcode automatic signing for generic iOS. It copies the
selected profile into the location Bazel expects.

Renewal still depends on Apple's signing service and a working Xcode account.
Reusing an unexpired profile does **not** extend its expiration date. Free Personal
Team signing still expires after seven days; this command does not schedule
automatic refreshes. The actual expiry is printed after each installation.

Refresh copies the app into private workflow storage and signs embedded frameworks
before signing the app. It preserves signed entitlements and verifies the result
with `codesign --verify --deep --strict`. It never uninstalls the phone's app or
changes the bundle ID, team or app groups. Separately provisioned extensions and
embedded watch apps are rejected. The local Xcode-managed development build
already disables these extensions.

To import a specific existing device build:

```sh
./install-iphone --app /absolute/path/to/Telegram.app
./install-iphone --configuration /absolute/path/to/local-development.json
./install-iphone --no-launch   # Install without opening the app
```

## Building and updating

`--build` synchronizes submodules, runs `build-system/Make/Make.py generateProject`
through `uv` with `--noOpenXcode`, then invokes `xcodebuild` for generic iOS. It uses
the existing `~/telegram-bazel-cache` and `build/XcodeDerivedData`. If installed
Xcode differs from `versions.json`, it prints the versions and deliberately uses
`--overrideXcodeVersion`. It does not clean Bazel caches.

`--update` first fetches the current branch's configured upstream. When behind,
it runs `git rebase --autostash` to replay local commits and preserve tracked
uncommitted edits. It does not push. Conflicts stop the command for resolution;
it does not guess how to merge source changes or discard edits. Use `git status`
to inspect recovery instructions, complete or abort the rebase, then rerun.
As with normal Git commands, untracked files that obstruct the update cause it to
stop, and modified submodules can require manual attention.

## Logs and recovery

State is under ignored `build/iphone-install/`:

- `current.json`: saved artifact, version, expiry and selected phone.
- `artifacts/`: private app copies; a successful run retains the current and
  preceding saved artifact. Failed runs retain their artifacts for diagnosis.
- `profile-helper/`: the reusable signing helper project and its build output.
- `logs/`: per-run command output and structured device results. `--verbose`
  also prints command lines. Logs stay local and are created with private permissions.

A signed artifact is saved before installation, so a disconnected phone does not
force another build. Rerun after reconnecting. If installation succeeds but launch
fails, the command exits with an error and preserves the app; the message includes
the device error and log path. An iOS signature/trust error can also affect an
ordinary Xcode build, so check the phone's developer trust and internet access.
`--no-launch` verifies installation metadata only, not whether iOS can run the app.

Exit codes: `0` success, `1` setup/build/signing/device failure, `2` invalid command
arguments, `130` interruption. Ctrl-C terminates the active command and its child
processes. Only one installer can run per checkout. `--status` and `--dry-run` do
not change state or contact Apple/the phone.

Run regression checks with:

```sh
uv run --no-project python -m unittest discover -s build-system/iphone -p 'test_*.py'
```

## Request a fresh signing profile

```sh
./install-iphone --renew-profile --dry-run
./install-iphone --renew-profile
./install-iphone --build --renew-profile
```

`--renew-profile` bypasses cached profiles for this exact app and team, builds the
small signing helper with Xcode's `-allowProvisioningUpdates`, and requires an
expiration later than the currently usable profile. It then re-signs and installs
the saved app (or the new build with `--build`). It cannot be combined with `--status`.

This forces a refresh attempt, not Apple's server to issue a new validity period.
In particular, Xcode may download the same unexpired Personal Team profile. In that
case the command exits with code 1 before signing or installing; it reports the
unchanged expiry. It does not revoke certificates, change capabilities, or change
the app identity. Normal signing remains available without this flag.

Cached profiles are copied to the run's `profile-backups/` directory before removal
and restored when the attempt finishes, fails, or is interrupted with Ctrl-C. On success, newly
downloaded files at the same paths are retained; on failure the originals are restored. Other apps' profiles are untouched.
For recovery after a power loss or forced process kill, `profile-backups/manifest.json`
records each backup and its original location. Close other Xcode builds for this app
while running the refresh, since they share the provisioning cache.
