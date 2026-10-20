import Foundation

public struct PeerId: Hashable {
    public let value: Int64

    public init(_ value: Int64) {
        self.value = value
    }
}

public protocol Peer: AnyObject {
    func isEqual(_ other: Peer) -> Bool
}

public func arePeersEqual(_ lhs: Peer?, _ rhs: Peer?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case let (lhs?, rhs?):
        return lhs.isEqual(rhs)
    default:
        return false
    }
}

public protocol PeerNotificationSettings: AnyObject {
    func isEqual(to other: PeerNotificationSettings) -> Bool
}

public enum PeerGroupId: Equatable {
    case root
    case group(Int32)
}

public enum PeerChatListInclusion {
    case notIncluded
    case included(PeerGroupId)

    public var groupId: PeerGroupId? {
        switch self {
        case .notIncluded:
            return nil
        case let .included(groupId):
            return groupId
        }
    }
}

public final class PeerTable {
    public var peer: Peer?

    public init(peer: Peer?) {
        self.peer = peer
    }

    public func get(_ peerId: PeerId) -> Peer? {
        return self.peer
    }
}

public final class PeerNotificationSettingsTable {
    public var settings: PeerNotificationSettings?

    public init(settings: PeerNotificationSettings? = nil) {
        self.settings = settings
    }

    public func getEffective(_ peerId: PeerId) -> PeerNotificationSettings? {
        return self.settings
    }
}

public final class ContactsTable {
    public var contact = false

    public func isContact(peerId: PeerId) -> Bool {
        return self.contact
    }
}

public final class ChatListPeerIndex {
    public var inclusion: PeerChatListInclusion

    public init(inclusion: PeerChatListInclusion) {
        self.inclusion = inclusion
    }
}

public final class ChatListIndexTable {
    public var index: ChatListPeerIndex

    public init(index: ChatListPeerIndex) {
        self.index = index
    }

    public func get(peerId: PeerId) -> ChatListPeerIndex {
        return self.index
    }
}

public final class PostboxImpl {
    public let peerTable: PeerTable
    public let peerNotificationSettingsTable: PeerNotificationSettingsTable
    public let contactsTable: ContactsTable
    public let chatListIndexTable: ChatListIndexTable

    public init(peer: Peer?, groupId: PeerGroupId) {
        self.peerTable = PeerTable(peer: peer)
        self.peerNotificationSettingsTable = PeerNotificationSettingsTable()
        self.contactsTable = ContactsTable()
        self.chatListIndexTable = ChatListIndexTable(index: ChatListPeerIndex(inclusion: .included(groupId)))
    }
}

public final class PostboxTransaction {
    public var currentUpdatedPeers: [PeerId: Peer] = [:]
    public var currentUpdatedPeerNotificationSettings: [PeerId: Bool] = [:]
    public var replaceContactPeerIds: Set<PeerId>?
    public var currentUpdatedChatListInclusions: [PeerId: Bool] = [:]
}

public protocol PostboxView {}

public protocol MutablePostboxView: AnyObject {
    func refreshDueToExternalTransaction(postbox: PostboxImpl) -> Bool
    func immutableView() -> PostboxView
}
