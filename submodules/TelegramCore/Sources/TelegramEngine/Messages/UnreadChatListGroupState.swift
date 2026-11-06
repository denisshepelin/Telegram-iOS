import Postbox
import SwiftSignalKit

func _internal_unreadChatListGroupState(postbox: Postbox, groupId: PeerGroupId, tags: PeerSummaryCounterTags, peerIds: Set<EnginePeer.Id>) -> Signal<(Int, [EnginePeer]), NoError> {
    var keys: [PostboxViewKey] = [
        .unreadCounts(items: [.totalInGroup(groupId)])
    ]
    keys.append(contentsOf: peerIds.map { .basicPeer($0) })

    return postbox.combinedView(keys: keys)
    |> map { combinedView -> (Int, [EnginePeer]) in
        var result = 0

        if let unreadCountsView = combinedView.views[keys[0]] as? UnreadMessageCountsView {
            for entry in unreadCountsView.entries {
                guard case let .totalInGroup(entryGroupId, unreadState) = entry, entryGroupId == groupId else {
                    continue
                }

                result += Int(unreadState.count(
                    for: .raw,
                    in: .chats,
                    with: tags
                ))
                break
            }
        }

        var peers: [EnginePeer] = []
        for peerId in peerIds {
            guard let peerView = combinedView.views[.basicPeer(peerId)] as? BasicPeerView,
                  peerView.groupId == groupId,
                  let peer = peerView.peer else {
                continue
            }

            peers.append(EnginePeer(peer))
        }

        return (result, peers)
    }
}
