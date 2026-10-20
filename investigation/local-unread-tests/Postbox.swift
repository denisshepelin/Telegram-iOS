import Foundation
import SwiftSignalKit

public struct PeerId: Hashable, Comparable, Codable {
    private let value: Int64

    public init(_ value: Int64) {
        self.value = value
    }

    public func toInt64() -> Int64 {
        return self.value
    }

    public static func < (lhs: PeerId, rhs: PeerId) -> Bool {
        return lhs.value < rhs.value
    }
}

public struct ValueBoxKey: Hashable {
    public let value: Int32

    public init(_ value: Int32) {
        self.value = value
    }
}

public struct ApplicationSpecificPreferencesKeys {
    public static let localUnreadIndicatorSettings = ValueBoxKey(23)
}

public enum UnreadMessageCountsItem: Hashable {
    case peer(id: PeerId, handleThreads: Bool)
}

public enum PostboxViewKey: Hashable {
    case messageHistoryThreadInfo(peerId: PeerId, threadId: Int64)
    case unreadCounts(items: [UnreadMessageCountsItem])
}

public final class PreferencesEntry {
    private let data: Data

    public init?<Value: Encodable>(_ value: Value?) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        self.data = data
    }

    public func get<Value: Decodable>(_ type: Value.Type) -> Value? {
        return try? JSONDecoder().decode(type, from: self.data)
    }
}

public final class PreferencesView {
    public let values: [ValueBoxKey: PreferencesEntry]

    public init(values: [ValueBoxKey: PreferencesEntry]) {
        self.values = values
    }
}

public struct StoredMessageHistoryThreadInfo: Equatable {
    public struct Summary: Equatable {
        public let totalUnreadCount: Int32
        public let isMarkedUnread: Bool
        public let mutedUntil: Int32?

        public init(totalUnreadCount: Int32, isMarkedUnread: Bool, mutedUntil: Int32?) {
            self.totalUnreadCount = totalUnreadCount
            self.isMarkedUnread = isMarkedUnread
            self.mutedUntil = mutedUntil
        }
    }

    public let summary: Summary

    public init(summary: Summary) {
        self.summary = summary
    }
}

public final class MessageHistoryThreadInfoView {
    public let info: StoredMessageHistoryThreadInfo?

    public init(info: StoredMessageHistoryThreadInfo?) {
        self.info = info
    }
}

public final class UnreadMessageCountsView {
    private let values: [PeerId: (Int32, Bool)]

    public init(values: [PeerId: (Int32, Bool)]) {
        self.values = values
    }

    public func countOrUnread(for item: UnreadMessageCountsItem) -> (Int32, Bool)? {
        guard case let .peer(id, _) = item else {
            return nil
        }
        return self.values[id]
    }
}

public final class CombinedView {
    public let views: [PostboxViewKey: Any]

    public init(views: [PostboxViewKey: Any]) {
        self.views = views
    }
}

public final class Transaction {
    private let postbox: Postbox

    fileprivate init(postbox: Postbox) {
        self.postbox = postbox
    }

    public func updatePreferencesEntry(key: ValueBoxKey, _ transform: (PreferencesEntry?) -> PreferencesEntry?) {
        self.postbox.preferences[key] = transform(self.postbox.preferences[key])
    }
}

public final class Postbox {
    fileprivate var preferences: [ValueBoxKey: PreferencesEntry] = [:]
    private var threadInfos: [String: StoredMessageHistoryThreadInfo] = [:]
    private var unreadStates: [PeerId: (Int32, Bool)] = [:]
    public private(set) var observedKeys: [PostboxViewKey] = []

    public init() {
    }

    private func threadKey(peerId: PeerId, threadId: Int64) -> String {
        return "\(peerId.toInt64()):\(threadId)"
    }

    public func setThreadInfo(peerId: PeerId, threadId: Int64, unreadCount: Int32, markedUnread: Bool = false, mutedUntil: Int32? = nil) {
        self.threadInfos[self.threadKey(peerId: peerId, threadId: threadId)] = StoredMessageHistoryThreadInfo(summary: .init(totalUnreadCount: unreadCount, isMarkedUnread: markedUnread, mutedUntil: mutedUntil))
    }

    public func setUnreadState(peerId: PeerId, count: Int32, markedUnread: Bool = false) {
        self.unreadStates[peerId] = (count, markedUnread)
    }

    public func preferencesView(keys: [ValueBoxKey]) -> Signal<PreferencesView, NoError> {
        return .single(PreferencesView(values: self.preferences.filter { keys.contains($0.key) }))
    }

    public func transaction(_ body: @escaping (Transaction) -> Void) -> Signal<Void, NoError> {
        body(Transaction(postbox: self))
        return .single(())
    }

    public func combinedView(keys: [PostboxViewKey]) -> Signal<CombinedView, NoError> {
        self.observedKeys = keys
        var views: [PostboxViewKey: Any] = [:]
        for key in keys {
            switch key {
            case let .messageHistoryThreadInfo(peerId, threadId):
                views[key] = MessageHistoryThreadInfoView(info: self.threadInfos[self.threadKey(peerId: peerId, threadId: threadId)])
            case let .unreadCounts(items):
                var values: [PeerId: (Int32, Bool)] = [:]
                for item in items {
                    if case let .peer(peerId, _) = item, let value = self.unreadStates[peerId] {
                        values[peerId] = value
                    }
                }
                views[key] = UnreadMessageCountsView(values: values)
            }
        }
        return .single(CombinedView(views: views))
    }
}
