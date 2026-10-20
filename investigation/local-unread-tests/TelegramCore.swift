import Postbox

public enum EnginePeer {
    public typealias Id = PeerId

    public struct Channel {
        public let id: PeerId
        public let isForumOrMonoForum: Bool

        public init(id: PeerId, isForumOrMonoForum: Bool) {
            self.id = id
            self.isForumOrMonoForum = isForumOrMonoForum
        }
    }

    case user(PeerId)
    case secretChat(PeerId)
    case community(PeerId)
    case legacyGroup(PeerId)
    case channel(Channel)

    public var id: PeerId {
        switch self {
        case let .user(id), let .secretChat(id), let .community(id), let .legacyGroup(id):
            return id
        case let .channel(channel):
            return channel.id
        }
    }
}

public enum EngineMessage {
    public struct Id: Equatable {
        public init() {
        }
    }
}

public enum EngineChatList {
    public final class ForumTopicData {
        public let id: Int64
        public let title: String
        public let iconFileId: Int64?
        public let iconColor: Int32
        public let maxOutgoingReadMessageId: EngineMessage.Id
        public let isUnread: Bool
        public let threadPeer: EnginePeer?

        public init(id: Int64, title: String, iconFileId: Int64?, iconColor: Int32, maxOutgoingReadMessageId: EngineMessage.Id, isUnread: Bool, threadPeer: EnginePeer?) {
            self.id = id
            self.title = title
            self.iconFileId = iconFileId
            self.iconColor = iconColor
            self.maxOutgoingReadMessageId = maxOutgoingReadMessageId
            self.isUnread = isUnread
            self.threadPeer = threadPeer
        }
    }
}
