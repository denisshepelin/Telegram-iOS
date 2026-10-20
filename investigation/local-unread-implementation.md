# Local unread indicators

| Conversation | Default | Opt-in behavior |
| --- | --- | --- |
| Private and secret chats, including bots | Normal Telegram unread dot/count | No opt-in needed |
| Groups without topics | No unread/activity badge | Long-press the chat → **Show unread dot** |
| Broadcast channels | No unread/activity badge | Long-press the channel → **Show unread dot** |
| Forum supergroups | No unread/activity badge | Long-press individual topics → **Show unread dot** |

A forum parent's dot is the OR of its selected topics' unread states. Unselected topics cannot light it up. The same topic ID in different groups is a different setting. Opting in does not enable push notifications or sounds, change mute settings, mark messages read, or change server counters. Muted selected topics can still light up the local dot. Selected groups/channels/topics show a dot, rather than a numerical unread counter. Private chats keep their normal numerical counters and normal mute styling.

Preferences are stored in the account's local Postbox preferences. They survive app restarts and are independent between accounts. No preference synchronization request is added. The menu offers **Hide unread dot** to remove an opt-in. The initial settings contain no opt-ins; no choices are inferred from existing mute settings.

The main chat list, archive rows, topic rows and search peer/topic results apply the policy at presentation time, leaving the raw read state available to mark-read actions and outgoing read receipts. Unread mention/reaction/poll badges are also suppressed for these group/channel rows so they cannot bypass the local dot policy. Saved Messages topic lists retain their existing behavior.

The archive reference combines maintained private-chat counters with one contribution per opted-in unread group/channel in the archive. Its preview peers use the same policy. This eliminates the old reflected type classifier and archive-wide cursor scan. Only selected topic IDs and opted-in peers are observed; updates cost work proportional to that selected set, not the archive size. Changes that leave the resulting policy state equal do not republish it.

The topic observer stores one map of known topic unread booleans: true means unread, false means read, and a missing entry means unavailable. Parent unread peers are derived from this map; there are no separately maintained parent or unavailable-topic collections. Archive counting calls the same presentation policy as chat and search rows, so its chat-type and forum rules cannot diverge. Settings normalize empty topic selections in one initializer.

The opted-in peer observer remains necessary: some native search paths expose only a message count and discard marked-unread state when that count is zero. Reusing those counts alone would lose opted-in dots. Search preserves the distinction between no unread state and marked-unread state with a zero message count.

Two small Postbox fixes reload subscribed topic/basic-peer views after external-process transactions. These keep selected-topic read state and archive membership current when an extension changes the database. No unread-counter maintenance algorithm or read-state write operation was changed.

## Verification

- Full Debug app build for the arm64 iOS simulator through the regenerated Xcode project: **BUILD SUCCEEDED** (Xcode 26.3).
- Swift frontend parsing of the changed production source files.
- Compiled tests of the actual preference source and chat policy helper against minimal Postbox/SignalKit/TelegramCore stubs: defaults, independent accounts, peer/topic updates, 64-bit identifier round trips, selected versus unselected and muted topics, unavailable topics, exact observed keys, private/group/channel/forum presentation, and search badges with absent, zero and positive unread counts.
- Compiled tests of the actual BasicPeerView source and extracted actual topic-view classes: unchanged, changed, removed and repeated missing external refreshes.
- `git diff --check`.
- The original migration patch was checked against temporary source copies before transfer. Later simplifications are reflected in the current source, not that historical patch.

Run the focused suites from the worktree:

```sh
investigation/local-unread-tests/run.sh
investigation/local-archive-tests/run.sh
```

These harnesses are not an iOS integration test and do not validate UIKit layout or real asynchronous Postbox delivery.

The successful build commands, run from the main checkout:

```sh
uv run build-system/Make/Make.py --overrideXcodeVersion --cacheDir="$HOME/telegram-bazel-cache" generateProject --configurationPath build-system/local-development.json --xcodeManagedCodesigning --target Telegram --noOpenXcode
xcodebuild -project Telegram/Telegram.xcodeproj -scheme Telegram -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/XcodeDerivedData CODE_SIGNING_ALLOWED=NO build
```

This checkout's Xcode project includes both device and simulator targets. Disabling provisioning profiles during generation failed device-target analysis, so generation used the existing local signing configuration; the simulator build itself had code signing disabled. A direct ChatListUI Bazel library build selected the macOS SDK and failed on UIKit, so validation used the app scheme. No build source changes were needed. No app was installed, no commit was created, and nothing was pushed.

## Remaining device checks and boundaries

1. Verify default suppression and each long-press toggle, including a selected topic older than the latest 20 topics.
2. Mark selected topics read, receive unread messages only in unselected topics, and toggle while the parent is visible. Confirm the parent dot follows only the selection.
3. Restart and switch accounts. Check a muted selected topic, moving an opted-in chat into/out of archive, and extension-side read changes.
4. Verify accessibility and that **Mark as read** still operates on actual unread state when its badge is hidden.
5. Compare optimized-build scan/CPU behavior under archived-message bursts. This implementation removes the identified full-scan path, but no battery improvement has been measured.

Selected topics need locally available topic state. Unavailable topic IDs are absent from the known-state map; this implementation does not fetch an entire forum or pretend to know an unloaded topic's unread count. Its dot appears when Postbox obtains the relevant unread state. The archive's maintained local private counters likewise cannot reconstruct the types of unseen server-only dialogs. Transient hidden/undo states are not subtracted from the maintained archive count. Telegram communities retain their existing normal indicators and are included in the maintained `nonContact` counter category.

Folder-tab totals, the global app badge, in-chat unread separators and push notifications retain Telegram's existing behavior; the local opt-ins control conversation-list indicators. New menu labels are currently English literals.
