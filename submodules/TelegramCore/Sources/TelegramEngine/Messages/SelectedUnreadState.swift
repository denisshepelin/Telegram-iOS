import Postbox
import SwiftSignalKit

func _internal_unreadPeerAndThreadStates(postbox: Postbox, peerIds: Set<EnginePeer.Id>, threadIds: [EnginePeer.Id: Set<Int64>]) -> Signal<(Set<EnginePeer.Id>, [EnginePeer.Id: [Int64: Bool]]), NoError> {
    var keys: [PostboxViewKey] = []
    for (peerId, threadIds) in threadIds {
        for threadId in threadIds {
            keys.append(.messageHistoryThreadInfo(peerId: peerId, threadId: threadId))
        }
    }

    let enabledPeerItems = peerIds.sorted().map { peerId in
        return UnreadMessageCountsItem.peer(id: peerId, handleThreads: false)
    }
    let enabledPeersKey: PostboxViewKey?
    if enabledPeerItems.isEmpty {
        enabledPeersKey = nil
    } else {
        let key = PostboxViewKey.unreadCounts(items: enabledPeerItems)
        enabledPeersKey = key
        keys.append(key)
    }

    if keys.isEmpty {
        return .single(([], [:]))
    }

    return postbox.combinedView(keys: keys)
    |> map { combinedView -> (Set<EnginePeer.Id>, [EnginePeer.Id: [Int64: Bool]]) in
        var topicUnreadStates: [PeerId: [Int64: Bool]] = [:]
        for (peerId, threadIds) in threadIds {
            for threadId in threadIds {
                let key = PostboxViewKey.messageHistoryThreadInfo(peerId: peerId, threadId: threadId)
                guard let info = (combinedView.views[key] as? MessageHistoryThreadInfoView)?.info else {
                    continue
                }
                topicUnreadStates[peerId, default: [:]][threadId] = info.summary.totalUnreadCount > 0 || info.summary.isMarkedUnread
            }
        }

        var unreadEnabledPeers = Set<PeerId>()
        if let enabledPeersKey, let view = combinedView.views[enabledPeersKey] as? UnreadMessageCountsView {
            for peerId in peerIds {
                let item = UnreadMessageCountsItem.peer(id: peerId, handleThreads: false)
                if let (count, markedUnread) = view.countOrUnread(for: item), count > 0 || markedUnread {
                    unreadEnabledPeers.insert(peerId)
                }
            }
        }

        return (unreadEnabledPeers, topicUnreadStates)
    }
}

