import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

/// Combines maintained private-chat archive totals with unread local group and topic opt-ins.
public func localArchiveUnreadCount(engine: TelegramEngine, state: LocalUnreadIndicatorState) -> Signal<Int, NoError> {
    let peerIds = state.unreadEnabledPeers.union(state.unreadSelectedPeers)
    return engine.messages.unreadChatListGroupState(group: .archive, tags: [.contact, .nonContact, .bot], peerIds: peerIds)
    |> map { unreadCount, peers -> Int in
        return unreadCount + peers.filter { peer in
            localChatUnreadIndicator(peer: peer, threadId: nil, isUnread: true, state: state) == .dot(true)
        }.count
    }
    |> distinctUntilChanged
}
