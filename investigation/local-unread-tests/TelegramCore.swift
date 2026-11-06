import Postbox
import SwiftSignalKit

public enum EnginePeer {
    public init(_ peer: TestPeer) {
        switch peer.kind {
        case .user: self = .user(peer.id)
        case .group: self = .legacyGroup(peer.id)
        case .forum: self = .channel(.init(id: peer.id, isForumOrMonoForum: true))
        }
    }
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
    public enum Group { case archive }
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

public typealias EnginePeerSummaryCounterTags = PeerSummaryCounterTags
public typealias EnginePreferencesEntry = PreferencesEntry
public struct ApplicationSpecificPreferencesKeys {
    public static let localUnreadIndicatorSettings = ValueBoxKey(23)
    public static let localMessageMuteSettings = ValueBoxKey(24)
}

public final class TelegramEngine {
    public let data: EngineData
    public let preferences: Preferences
    public let messages: Messages

    public init(postbox: Postbox) {
        self.data = EngineData(postbox: postbox)
        self.preferences = Preferences(postbox: postbox)
        self.messages = Messages(postbox: postbox)
    }

    public final class EngineData {
        public enum Item {
            public enum Configuration {
                public struct ApplicationSpecificPreference {
                    let key: ValueBoxKey
                    public init(key: ValueBoxKey) { self.key = key }
                }
            }
        }
        let postbox: Postbox
        init(postbox: Postbox) { self.postbox = postbox }
        public func subscribe(_ item: Item.Configuration.ApplicationSpecificPreference) -> Signal<PreferencesEntry?, NoError> {
            return self.postbox.preferencesView(keys: [item.key]) |> map { $0.values[item.key] }
        }
    }

    public final class Preferences {
        let postbox: Postbox
        init(postbox: Postbox) { self.postbox = postbox }
        public func update(id: ValueBoxKey, _ transform: @escaping (PreferencesEntry?) -> PreferencesEntry?) -> Signal<Never, NoError> {
            return Signal { _ in
                self.postbox.transaction { transaction in
                    transaction.updatePreferencesEntry(key: id, transform)
                }.start(next: { _ in })
            }
        }
    }

    public final class Messages {
        let postbox: Postbox
        init(postbox: Postbox) { self.postbox = postbox }
        public func unreadChatListGroupState(group: EngineChatList.Group, tags: PeerSummaryCounterTags, peerIds: Set<EnginePeer.Id>) -> Signal<(Int, [EnginePeer]), NoError> {
            return _internal_unreadChatListGroupState(postbox: self.postbox, groupId: PeerGroupId(rawValue: 1), tags: tags, peerIds: peerIds)
        }
        public func unreadPeerAndThreadStates(peerIds: Set<EnginePeer.Id>, threadIds: [EnginePeer.Id: Set<Int64>]) -> Signal<(Set<EnginePeer.Id>, [EnginePeer.Id: [Int64: Bool]]), NoError> {
            return _internal_unreadPeerAndThreadStates(postbox: self.postbox, peerIds: peerIds, threadIds: threadIds)
        }
    }
}
