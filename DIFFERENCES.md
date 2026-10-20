# CalmGram changes from upstream

The upstream repository is `TelegramMessenger/Telegram-iOS`, tracked as
`origin/master`. Local changes are committed on `master`.

| Area | Local behavior |
| --- | --- |
| App name | The installed app is named CalmGram. |
| Links | System default browser is an explicit option. |
| Stories | Stories and their chat-list affordances can be hidden. |
| Message muting | Messages from locally muted accounts can be temporarily revealed. |
| Unread indicators | Private chats retain normal indicators. Groups and channels show no indicator by default, with an opt-in unread dot. Forum dots reflect only selected topics. |
| Reader | Eligible message text can be opened in Reader mode. |
| Sponsored content | Builds with `--disable-ads` hide ad rendering while retaining ad requests. |
| Local development | Device and simulator project generation, writable build products, and command-line iPhone signing and installation. |

## Compare local work with upstream

```sh
git fetch origin
git log --oneline origin/master..HEAD
git diff --stat origin/master...HEAD
git show <commit>
```

The build integration also has local commits in the `rules_xcodeproj` submodule.
The parent repository records their exact revisions. Those commits must be
published to an accessible submodule remote before sharing the parent commits
with another checkout.

See [the iPhone installer guide](build-system/iphone/README.md) for builds and
installation, and [the unread indicator notes](investigation/local-unread-implementation.md)
for policy details and focused checks. Signing credentials and generated editor
files remain local and are not part of the commits.
