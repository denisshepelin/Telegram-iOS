#!/bin/sh
set -eu

test_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_root=$(mktemp -d "${TMPDIR:-/tmp}/local-unread-tests.XXXXXX")
trap 'rm -rf "$build_root"' EXIT

swiftc -parse-as-library -emit-module -emit-object -emit-module-path "$build_root/SwiftSignalKit.swiftmodule" -module-name SwiftSignalKit "$test_root/SwiftSignalKit.swift" -o "$build_root/SwiftSignalKit.o"
swiftc -parse-as-library -emit-module -emit-object -emit-module-path "$build_root/Postbox.swiftmodule" -module-name Postbox -I "$build_root" "$test_root/Postbox.swift" -o "$build_root/Postbox.o"
swiftc -parse-as-library -emit-module -emit-object -emit-module-path "$build_root/TelegramCore.swiftmodule" -module-name TelegramCore -whole-module-optimization -I "$build_root" "$test_root/TelegramCore.swift" "$test_root/../../submodules/TelegramCore/Sources/TelegramEngine/Messages/SelectedUnreadState.swift" "$test_root/../../submodules/TelegramCore/Sources/TelegramEngine/Messages/UnreadChatListGroupState.swift" -o "$build_root/TelegramCore.o"
swiftc -parse-as-library -emit-module -emit-object -emit-module-path "$build_root/TelegramUIPreferences.swiftmodule" -module-name TelegramUIPreferences -whole-module-optimization -I "$build_root" "$test_root/../../submodules/TelegramUIPreferences/Sources/LocalUnreadIndicatorSettings.swift" "$test_root/../../submodules/TelegramUIPreferences/Sources/LocalMessageMuteSettings.swift" -o "$build_root/TelegramUIPreferences.o"
{
    printf '%s\n' 'import TelegramCore' 'import TelegramUIPreferences'
    awk '/^private func localUnreadIndicatorBadge/,/^}$/ { sub(/^private func localUnreadIndicatorBadge/, "func localUnreadIndicatorBadge"); print }' "$test_root/../../submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift"
} > "$build_root/LocalUnreadIndicatorBadge.swift"
swiftc -I "$build_root" "$test_root/../../submodules/ChatListUI/Sources/Node/LocalChatUnreadIndicator.swift" "$build_root/LocalUnreadIndicatorBadge.swift" "$test_root/../../submodules/ChatListUI/Sources/Node/LocalArchiveUnreadIndicator.swift" "$test_root/ChatListItemStubs.swift" "$test_root/LocalUnreadIndicatorSettingsTests.swift" "$build_root/SwiftSignalKit.o" "$build_root/Postbox.o" "$build_root/TelegramCore.o" "$build_root/TelegramUIPreferences.o" -o "$build_root/local-unread-tests"
"$build_root/local-unread-tests"
