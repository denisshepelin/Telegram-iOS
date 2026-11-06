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


public enum UnreadMessageCountsItem: Hashable {
    case peer(id: PeerId, handleThreads: Bool)
    case totalInGroup(PeerGroupId)
}

public enum PostboxViewKey: Hashable {
    case basicPeer(PeerId)
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
    public enum Entry { case totalInGroup(PeerGroupId, TestUnreadTotals) }
    public let entries: [Entry]
    private let values: [PeerId: (Int32, Bool)]

    public init(values: [PeerId: (Int32, Bool)], entries: [Entry] = []) {
        self.entries = entries
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
    public var archiveTotals = TestUnreadTotals(counts: [:])
    public var basicPeers: [PeerId: BasicPeerView] = [:]
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
            case let .basicPeer(peerId):
                views[key] = basicPeers[peerId] ?? BasicPeerView(groupId: nil, peer: nil)
            case let .messageHistoryThreadInfo(peerId, threadId):
                views[key] = MessageHistoryThreadInfoView(info: self.threadInfos[self.threadKey(peerId: peerId, threadId: threadId)])
            case let .unreadCounts(items):
                var values: [PeerId: (Int32, Bool)] = [:]
                for item in items {
                    if case let .peer(peerId, _) = item, let value = self.unreadStates[peerId] {
                        values[peerId] = value
                    }
                }
                let entries = items.compactMap { item -> UnreadMessageCountsView.Entry? in
                    if case let .totalInGroup(groupId) = item { return .totalInGroup(groupId, self.archiveTotals) }
                    return nil
                }
                views[key] = UnreadMessageCountsView(values: values, entries: entries)
            }
        }
        return .single(CombinedView(views: views))
    }
}

public struct PeerGroupId: Hashable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
}
public struct PeerSummaryCounterTags: OptionSet, Hashable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let contact = Self(rawValue: 1)
    public static let nonContact = Self(rawValue: 2)
    public static let bot = Self(rawValue: 4)
    public static let group = Self(rawValue: 8)
}
public struct TestUnreadTotals {
    public enum Category { case raw }
    public enum Stats { case chats }
    public let counts: [PeerSummaryCounterTags: Int32]
    public init(counts: [PeerSummaryCounterTags: Int32]) { self.counts = counts }
    public func count(for category: Category, in stats: Stats, with tags: PeerSummaryCounterTags) -> Int32 {
        return self.counts.reduce(0) { $0 + (tags.contains($1.key) ? $1.value : 0) }
    }
}
public struct TestPeer {
    public enum Kind { case user, group, forum }
    public let id: PeerId
    public let kind: Kind
    public init(id: PeerId, kind: Kind) { self.id = id; self.kind = kind }
}
public struct BasicPeerView {
    public let groupId: PeerGroupId?
    public let peer: TestPeer?
    public init(groupId: PeerGroupId?, peer: TestPeer?) { self.groupId = groupId; self.peer = peer }
}
