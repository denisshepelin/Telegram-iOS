import Foundation

public struct PeerId: Hashable {
    public let value: Int64

    public init(_ value: Int64) {
        self.value = value
    }
}

public struct StoredMessageHistoryThreadInfo: Equatable {
    public let unreadCount: Int32

    public init(unreadCount: Int32) {
        self.unreadCount = unreadCount
    }
}

public final class MessageHistoryThreadIndexTable {
    private struct Key: Hashable {
        let peerId: PeerId
        let threadId: Int64
    }

    private var entries: [Key: StoredMessageHistoryThreadInfo] = [:]

    public func get(peerId: PeerId, threadId: Int64) -> StoredMessageHistoryThreadInfo? {
        return self.entries[Key(peerId: peerId, threadId: threadId)]
    }

    public func set(_ info: StoredMessageHistoryThreadInfo?, peerId: PeerId, threadId: Int64) {
        let key = Key(peerId: peerId, threadId: threadId)
        if let info {
            self.entries[key] = info
        } else {
            self.entries.removeValue(forKey: key)
        }
    }
}

public final class PostboxImpl {
    public let messageHistoryThreadIndexTable = MessageHistoryThreadIndexTable()
}

public final class PostboxTransaction {
    public var updatedMessageThreadPeerIds = Set<PeerId>()
}

public protocol PostboxView {}

public protocol MutablePostboxView: AnyObject {
    func replay(postbox: PostboxImpl, transaction: PostboxTransaction) -> Bool
    func refreshDueToExternalTransaction(postbox: PostboxImpl) -> Bool
    func immutableView() -> PostboxView
}
