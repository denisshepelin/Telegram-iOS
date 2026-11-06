# Local unread indicator harness

Run `./run.sh` from this directory, or `investigation/local-unread-tests/run.sh` from the repository root.

The harness compiles the production local unread and message-mute settings, selected-peer/topic and archive queries, and chat-list presentation helpers against minimal local Postbox, TelegramCore, and SignalKit stubs. It exercises settings Codable/persistence, account isolation, exact selected-topic observation, mute-independent unread summaries, archive membership, and presentation policy for private chats, groups, broadcast channels, and forums. Database queries run through the same TelegramEngine-facing calls used by the app.

This is a focused policy harness; it is not a full Telegram iOS or Bazel build. The separate `investigation/local-archive-tests/run.sh` harness compiles the actual basic-peer view and extracts the actual topic-view classes to check external-transaction refresh behavior.
