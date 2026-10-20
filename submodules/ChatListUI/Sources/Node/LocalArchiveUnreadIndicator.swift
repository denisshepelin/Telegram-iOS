import Postbox
import TelegramCore
import TelegramUIPreferences
import SwiftSignalKit

/// Counts unread archive chats covered by the local unread indicator policy.
///
/// The maintained archive counters provide the normal count for users, secret
/// chats, bots, and communities. Locally enabled legacy groups and channels
/// are then added individually after checking their current chat-list group.
/// Communities currently use the `nonContact` counter tag, so they remain in
/// the normal private count and are intentionally excluded from the opt-in
/// additions. If the archive counter is unavailable or has not been populated,
/// the private portion of the result is zero until Postbox publishes it.
public func localArchiveUnreadCount(postbox: Postbox, state: LocalUnreadIndicatorState) -> Signal<Int, NoError> {
    let archiveGroupId = PeerGroupId(rawValue: 1)
    let locallyUnreadPeerIds = state.unreadEnabledPeers.union(state.unreadSelectedPeers)
    let peerIds = Array(locallyUnreadPeerIds)

    var keys: [PostboxViewKey] = [
        .unreadCounts(items: [.totalInGroup(archiveGroupId)])
    ]
    keys.append(contentsOf: peerIds.map { .basicPeer($0) })

    return postbox.combinedView(keys: keys)
    |> map { combinedView -> Int in
        var result = 0

        if let unreadCountsView = combinedView.views[keys[0]] as? UnreadMessageCountsView {
            for entry in unreadCountsView.entries {
                guard case let .totalInGroup(groupId, unreadState) = entry, groupId == archiveGroupId else {
                    continue
                }

                result += Int(unreadState.count(
                    for: .raw,
                    in: .chats,
                    with: [.contact, .nonContact, .bot]
                ))
                break
            }
        }

        for peerId in peerIds {
            guard let peerView = combinedView.views[.basicPeer(peerId)] as? BasicPeerView,
                  peerView.groupId == archiveGroupId,
                  let peer = peerView.peer else {
                continue
            }

            if localChatUnreadIndicator(peer: EnginePeer(peer), threadId: nil, isUnread: true, state: state) == .dot(true) {
                result += 1
            }
        }

        return result
    }
    |> distinctUntilChanged
}
