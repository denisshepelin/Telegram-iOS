# AGENTS.md

Guidance for coding agents working in this repository. The project guide is [`CLAUDE.md`](CLAUDE.md): how to build,
which simulators to use, how to drive them (XcodeBuildMCP) and the invariants of each subsystem. Read it first.

## Visual features and animations: judge them from recorded frames

A green build and passing unit tests say nothing about how a change looks or moves. For any visual change, and always
for one that animates, record the simulator while it happens, turn the recording into images of its frames labelled
with their index and time, and evaluate the animation from those before calling the work done. Unit tests pin the
model (a choreography's values, a layout's frames); only the frames show what is drawn: what is clipped, what pops in,
what moves together and what lags, where it overshoots and whether it settles.

### 1. Know what correct looks like first

Write down, before recording, what the frames should show: which elements move, which move together, the direction,
roughly how long, whether a spring should overshoot and how many times, what must never be visible (a gap, a clipped
edge, an element standing still while its neighbours move). The evaluation is a comparison against this; without it
the frames only get described.

### 2. Record

Recording is passive: it does not touch the installed app or its state. Installing or replacing the app is not; follow
`CLAUDE.md` and the user's standing instructions on which simulator an agent may install on, and otherwise ask the user
to install the build and then record what they or you trigger.

```sh
U=<simulator udid>                       # xcrun simctl list devices booted
OUT=<scratch directory>                  # not the repo
xcrun simctl io "$U" recordVideo --codec=h264 --force "$OUT/anim.mp4" > "$OUT/rec.log" 2>&1 &
REC=$!
until grep -q "Recording started" "$OUT/rec.log"; do sleep 0.1; done
# … trigger the animation: XcodeBuildMCP taps/swipes, a deep link (xcrun simctl openurl), or ask the user …
sleep 1                                  # let it settle on camera
kill -INT $REC; wait $REC                # SIGINT finalizes the file
```

- Use `simctl io recordVideo`, not XcodeBuildMCP's `record_sim_video`: the latter resamples to a fixed rate (30 fps by
  default), which hides exactly the frame-level detail being looked for.
- The recording is **variable-rate**. The simulator writes a frame only when the screen changes, stamped with its own
  time (1/600 s units), at the display's rate while something moves (16.7 ms median on an iPhone 17 / iOS 26.5
  simulator, 10 ms on the iPhone 18 Pro / iOS 27 one; the script prints it). A still screen produces no frames, so a
  stall appears as one long interval, and time must always come from a frame's timestamp, never from its index. It
  also writes the odd near-copy a few ms after a frame.
- **Take the timestamps from `ffprobe`, never from `ffmpeg`.** The file can carry a duplicated timestamp, after which
  `ffmpeg` (its `showinfo`, its `select` on `t`) falls back to each frame's decode time, seconds behind (measured:
  11.66 s, then 8.07 s for the next frame); the frames themselves still come out in order. The script handles this;
  anything hand-rolled must too.
- Frames are the device's pixels (3x: a 402 × 874 pt screen records at 1206 × 2622).
- A tap at a point, where XcodeBuildMCP offers only element taps: `axe touch -x X -y Y --down --up --delay 0.08
  --udid "$U"` (points). Issue it in the same shell command as the recording, so the tap lands a known time into it.
- Record the whole gesture with a little still time on both sides, once per path the change touches (open and close,
  each entry point, light and dark, with and without the optional content), and in slow motion only in addition to
  real speed, never instead: timing is part of what is being judged.

### 3. Turn it into frames

```sh
python3 tools/animation_sheet.py "$OUT/anim.mp4" "$OUT/sheet" --start 0.4 --end 1.6 \
  [--crop X,Y,W,H] [--track NAME=X,Y,W,H ...] [--tile-width 200] [--columns 8] [--rows 4]
```

All geometry is in points (the recording's pixels over `--scale`, 3 by default): `--crop`, `--track` and every number
it prints.

It writes, into the output directory:

- `sheet-NN.png`: every frame in the range, tiled in time order, each labelled `#index  t=seconds  +ms since the
  previous frame`, with flagged frames framed in red. Open them with the image-reading tool.
- `motion.png`: per frame, how much the picture changed since the previous frame (bars), the interval since the
  previous frame (dots, dashes at the median) and how far the picture still is from the last frame (green line).
- `tracks.png` (with `--track`): each tracked region's offset from its resting place per frame, one line each.
- `frames.tsv`: the same numbers per frame, with the region that changed and each track's offset and match error.
- `frames/NNNNN.png`: the frames themselves, numbered as on the sheets.

and prints a summary: when the motion starts and stops, when it comes within 2% of its resting state for good, every
time it passes its rest and comes back out (a spring's overshoot, an oscillation), every flagged frame, each track's
path and how far apart the tracks ever are:

- `gap`: an interval over 1.5x the median while the picture changes by at least 5% of the clip's largest change: a
  frame drawn late, or a stall (a spinner or caret drawing at its own lower rate is not counted).
- `jump`: a frame that changed over 3x as much as the frames around it: a snap, a teleport, something appearing or
  vanishing at once in the middle of smooth motion.

**Tracks are the precise instrument.** `--track NAME=X,Y,W,H` names a region of the LAST frame (the rest; for
something leaving, a close, pass `--track-reference first` and name it in the first frame); in every frame the script finds where that content stands, shifted vertically, and reports the offset in points: negative
above its rest, positive below, 0 at rest. One track gives an element's real path (where it starts, how far past its
rest it goes, when it is within 1 pt); several give "these move together" as a number: in every frame where all are
found their offsets must agree. Pick each region inside one element, with texture (text, icons, edges), clear of
anything that moves differently, and get its coordinates from the last frame (`frames/` holds it at points scale).
Matches are only as good as the template: text that is still changing size or colour, or that lies over content
changing behind it (a photo, a pattern fading in), reads as not found (`-`) or, worse, as a confident wrong offset in a
handful of frames; rows that look alike (list rows) can match one another. Trust a stretch where several tracks
agree, and check a disagreement on the sheet before reporting it.

Use `--start`/`--end` to keep only the motion (the summary's times are the recording's own clock) and `--crop` to look
at one part of the screen: the distance-from-rest curve and the change bars measure whatever is in the picture. Mind
the scale: a 200 px tile of a 402 pt screen is half a pixel per point, so a 9 pt overshoot moves 4–5 px on the sheet;
crop and raise `--tile-width` until the motion being judged is visible.

### 4. Evaluate

- **Shape.** The green line is the motion's shape: an ease-out falls to 0 and stays; a spring falls, touches its rest
  and rises again by its overshoot before settling, once per oscillation; a step in it is a hitch. Compare the summary's
  duration, settle time and passes with what was intended. The pass percentages are of the picture's difference, not
  of the travel distance: use them to tell whether it overshoots and how many times, and read the amount off the
  frames.
- **Togetherness.** For "these move together", track each element: elements that move as one stand at the same
  offset in every frame, overshoot included, which the summary's pairwise "apart by at most" states. An element that
  rests while its neighbours move, arrives a frame late or overshoots alone is the defect class this catches. Elements
  on one spring but with different travel overshoot in proportion to their travel: same phase, different amplitude.
- **Every flagged frame.** Open the tiles around it and say what it is. A `jump` can be legitimate (an element meant
  to appear at once); a `gap` on the simulator can be the Mac's. A gap that recurs at the same point across several
  recordings is the app's; frame pacing itself is confirmed on a device, not the simulator.
- **The frames, not just the numbers.** Read the sheets end to end for what no metric sees: clipping, a wrong z-order
  for a frame, a colour flash, text re-wrapping mid-flight, an element drawn twice during a hand-over.

Report findings with their evidence, by frame: "#23–#31 (t=0.512–0.645): the list stays at rest while the buttons
overshoot 9 pt" names something another agent or the user can open and check. A claim about an animation without frame
references has not been verified.

## Local development guidance

This file provides guidance to AI assistants when working with code in this repository.

## Build
The app is built using Bazel.

## Bazel Lifecycle
- Treat `build-system/Make/Make.py` as the entrypoint for local Bazel work. In this repo, run it through `uv`, not plain `python`.
- For local simulator work, prefer regenerating the Xcode project with `generateProject` over editing generated files under `Telegram/Telegram.xcodeproj` or anything in `bazel-out`.
- Keep a persistent local cache such as `--cacheDir="$HOME/telegram-bazel-cache"` for iteration speed.
- If local Xcode does not match `versions.json`, use `--overrideXcodeVersion` deliberately rather than debugging unrelated Bazel failures first.
- For simulator-only builds, use `--disableProvisioningProfiles`. Device signing requirements should not leak into the simulator lifecycle.
- If Xcode reports `Telegram_xcodeproj: no such package`, or after pulling/rebasing changes that affect Bazel, regenerate the project before trying deeper cleanup.
- After pulling new commits, especially when submodule pointers change, run `git submodule update --init --recursive` before assuming the Bazel graph is broken.
- Avoid `clean` / `bazel clean --expunge` unless there is a concrete cache corruption or toolchain state problem. Prefer project regeneration and a rebuild first.
- Do not treat artifacts under `/var/tmp/_bazel_*`, `build-input/`, `bazel-bin/`, or the generated `.xcodeproj` as durable hand-edited state. Fix the source Bazel rules or the project-generation code instead.

## Device Build Notes
- For local iPhone installs, generate the project with `--xcodeManagedCodesigning`; if local Xcode is newer than `versions.json`, pair it with `--overrideXcodeVersion`.
- If the device does not appear in Xcode run destinations, make sure the `xcodeproj` top-level target includes both `device` and `simulator`, then regenerate the project and reopen Xcode.
- `build-system/local-development.json` `team_id` must match the provisioning profile team or the Apple Development certificate subject OU. Do not rely only on the team shown in the certificate display label.
- If Xcode says no provisioning profile exists for the bundle ID, create a tiny temporary iOS app with the same bundle identifier, enable automatic signing for the same team, and build it once to the target phone to force Xcode to mint the profile.
- On this setup, Xcode-managed provisioning profiles were under `~/Library/Developer/Xcode/UserData/Provisioning Profiles`, not `~/Library/MobileDevice/Provisioning Profiles`.
- If framework builds fail while copying `.swiftmodule`, `.swiftdoc`, `.swiftsourceinfo`, or writing framework `Info.plist` files with permission errors, suspect macOS `openrsync` leaving copied Bazel bundles read-only. Fix the source `copy_outputs.sh`, regenerate the project, reopen Xcode, and clean the build folder before debugging anything deeper.
- After fixing a build issue, prefer the latest entry in Xcode's Report Navigator over the Issues pane, which can keep stale errors from earlier builds.

## Code Style Guidelines
- **Naming**: PascalCase for types, camelCase for variables/methods
- **Imports**: Group and sort imports at the top of files
- **Error Handling**: Properly handle errors with appropriate redaction of sensitive data
- **Formatting**: Use standard Swift/Objective-C formatting and spacing
- **Types**: Prefer strong typing and explicit type annotations where needed
- **Documentation**: Document public APIs with comments

## Project Structure
- Core launch and application extensions code is in `Telegram/` directory
- Most code is organized into libraries in `submodules/`
- External code is located in `third-party/`
- No tests are used at the moment
