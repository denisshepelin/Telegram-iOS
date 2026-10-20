# Local unread indicator harness

Run `./run.sh` from this directory, or `investigation/local-unread-tests/run.sh` from the repository root.

The harness compiles the production `LocalUnreadIndicatorSettings.swift` and `LocalChatUnreadIndicator.swift` files against minimal local Postbox, TelegramCore, and SignalKit stubs. It exercises settings Codable/persistence, exact selected-topic policy, mute-independent unread summaries, and presentation policy for private chats, groups, broadcast channels, and forums.

This is a focused policy harness; it is not a full Telegram iOS or Bazel build. The separate `investigation/local-archive-tests/run.sh` harness compiles the actual basic-peer view and extracts the actual topic-view classes to check external-transaction refresh behavior.
