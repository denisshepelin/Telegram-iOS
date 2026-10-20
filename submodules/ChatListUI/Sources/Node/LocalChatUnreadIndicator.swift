import TelegramCore
import TelegramUIPreferences

func localChatUnreadIndicator(peer: EnginePeer?, threadId: Int64?, isUnread: Bool, state: LocalUnreadIndicatorState) -> ChatListUnreadIndicator {
    guard let peer else {
        return .normal
    }
    switch peer {
    case .user, .secretChat, .community:
        return .normal
    case .legacyGroup, .channel:
        if let threadId {
            guard state.settings.isTopicEnabled(peerId: peer.id, threadId: threadId) else {
                return .hidden
            }
            return .dot(state.topicUnreadStates[peer.id]?[threadId] ?? isUnread)
        }

        let isForum: Bool
        if case let .channel(channel) = peer {
            isForum = channel.isForumOrMonoForum
        } else {
            isForum = false
        }
        let isPeerEnabled = !isForum && state.settings.isPeerEnabled(peerId: peer.id)
        guard isPeerEnabled || state.settings.enabledTopics[peer.id]?.isEmpty == false else {
            return .hidden
        }
        return .dot((state.topicUnreadStates[peer.id]?.values.contains(true) == true) || (isPeerEnabled && state.unreadEnabledPeers.contains(peer.id)))
    }
}

func localChatTopicUnreadPresentation(_ topic: EngineChatList.ForumTopicData, peer: EnginePeer?, state: LocalUnreadIndicatorState) -> EngineChatList.ForumTopicData {
    let indicator = localChatUnreadIndicator(peer: peer, threadId: topic.id, isUnread: topic.isUnread, state: state)
    let isUnread: Bool
    switch indicator {
    case .normal:
        isUnread = topic.isUnread
    case .hidden:
        isUnread = false
    case let .dot(value):
        isUnread = value
    }
    guard topic.isUnread != isUnread else {
        return topic
    }
    return EngineChatList.ForumTopicData(id: topic.id, title: topic.title, iconFileId: topic.iconFileId, iconColor: topic.iconColor, maxOutgoingReadMessageId: topic.maxOutgoingReadMessageId, isUnread: isUnread, threadPeer: topic.threadPeer)
}
