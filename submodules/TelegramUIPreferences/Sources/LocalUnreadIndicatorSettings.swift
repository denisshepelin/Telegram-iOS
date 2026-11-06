import Foundation
import TelegramCore
import SwiftSignalKit

/// Stores per-account local unread indicator opt-ins for peers and forum topics.
public struct LocalUnreadIndicatorSettings: Codable, Equatable {
    /// Peers whose regular unread indicator is enabled locally.
    public let enabledPeers: Set<EnginePeer.Id>
    /// Forum topics selected locally for a parent peer unread dot.
    public let enabledTopics: [EnginePeer.Id: Set<Int64>]

    /// Returns settings with no group, channel, or topic opt-ins.
    public static var defaultSettings: LocalUnreadIndicatorSettings {
        return LocalUnreadIndicatorSettings(enabledPeers: [], enabledTopics: [:])
    }

    /// Creates local unread indicator settings for one account.
    public init(enabledPeers: Set<EnginePeer.Id>, enabledTopics: [EnginePeer.Id: Set<Int64>]) {
        self.enabledPeers = enabledPeers
        self.enabledTopics = enabledTopics.filter { !$0.value.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case enabledPeers = "peers"
        case enabledTopics = "topics"
    }

    private struct TopicEntry: Codable {
        let peerId: Int64
        let threadIds: [Int64]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let peerIds = try container.decodeIfPresent([Int64].self, forKey: .enabledPeers) ?? []
        let topicEntries = try container.decodeIfPresent([TopicEntry].self, forKey: .enabledTopics) ?? []

        var topics: [EnginePeer.Id: Set<Int64>] = [:]
        for entry in topicEntries {
            topics[EnginePeer.Id(entry.peerId)] = Set(entry.threadIds)
        }

        self.init(enabledPeers: Set(peerIds.map(EnginePeer.Id.init)), enabledTopics: topics)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.enabledPeers.map { $0.toInt64() }.sorted(), forKey: .enabledPeers)

        let topicEntries = self.enabledTopics.map { peerId, threadIds in
            return TopicEntry(peerId: peerId.toInt64(), threadIds: threadIds.sorted())
        }.sorted { lhs, rhs in
            return lhs.peerId < rhs.peerId
        }
        try container.encode(topicEntries, forKey: .enabledTopics)
    }

    /// Returns whether a peer has a local regular unread indicator opt-in.
    public func isPeerEnabled(peerId: EnginePeer.Id) -> Bool {
        return self.enabledPeers.contains(peerId)
    }

    /// Returns whether one exact forum topic has a local unread indicator opt-in.
    public func isTopicEnabled(peerId: EnginePeer.Id, threadId: Int64) -> Bool {
        return self.enabledTopics[peerId]?.contains(threadId) ?? false
    }

    /// Returns settings with one peer's local unread indicator opt-in changed.
    public func withUpdatedPeer(peerId: EnginePeer.Id, enabled: Bool) -> LocalUnreadIndicatorSettings {
        var peers = self.enabledPeers
        if enabled {
            peers.insert(peerId)
        } else {
            peers.remove(peerId)
        }
        return LocalUnreadIndicatorSettings(enabledPeers: peers, enabledTopics: self.enabledTopics)
    }

    /// Returns settings with one exact forum topic's local unread indicator opt-in changed.
    public func withUpdatedTopic(peerId: EnginePeer.Id, threadId: Int64, enabled: Bool) -> LocalUnreadIndicatorSettings {
        var topics = self.enabledTopics
        if enabled {
            topics[peerId, default: []].insert(threadId)
        } else {
            topics[peerId]?.remove(threadId)
        }
        return LocalUnreadIndicatorSettings(enabledPeers: self.enabledPeers, enabledTopics: topics)
    }
}

/// Reads local unread indicator settings for one account from Postbox preferences.
public func localUnreadIndicatorSettings(engine: TelegramEngine) -> Signal<LocalUnreadIndicatorSettings, NoError> {
    return engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.localUnreadIndicatorSettings))
    |> map { entry -> LocalUnreadIndicatorSettings in
        return entry?.get(LocalUnreadIndicatorSettings.self) ?? .defaultSettings
    }
    |> distinctUntilChanged
}

/// Applies a local unread indicator settings update without writing to Telegram's server state.
public func updateLocalUnreadIndicatorSettingsInteractively(engine: TelegramEngine, _ transform: @escaping (LocalUnreadIndicatorSettings) -> LocalUnreadIndicatorSettings) -> Signal<Never, NoError> {
    return engine.preferences.update(id: ApplicationSpecificPreferencesKeys.localUnreadIndicatorSettings, { entry in
        let currentSettings = entry?.get(LocalUnreadIndicatorSettings.self) ?? .defaultSettings
        return EnginePreferencesEntry(transform(currentSettings))
    })
}

/// Combines local unread settings with unread state from only the selected exact forum topics.
public struct LocalUnreadIndicatorState: Equatable {
    /// Current local per-account unread indicator settings.
    public let settings: LocalUnreadIndicatorSettings
    /// Enabled non-forum peers with unread messages, independent of notification mute state.
    public let unreadEnabledPeers: Set<EnginePeer.Id>
    /// Known selected topic states: true is unread, false is read, and a missing entry is unavailable.
    public let topicUnreadStates: [EnginePeer.Id: [Int64: Bool]]

    /// Derives parent unread dots from the exact selected topic states.
    public var unreadSelectedPeers: Set<EnginePeer.Id> {
        return Set(self.topicUnreadStates.compactMap { $0.value.values.contains(true) ? $0.key : nil })
    }

    /// Creates a local unread indicator policy state.
    public init(settings: LocalUnreadIndicatorSettings, unreadEnabledPeers: Set<EnginePeer.Id> = [], topicUnreadStates: [EnginePeer.Id: [Int64: Bool]] = [:]) {
        self.settings = settings
        self.unreadEnabledPeers = unreadEnabledPeers
        self.topicUnreadStates = topicUnreadStates
    }
}

/// Observes local settings and unread summaries for exactly the selected forum topic IDs.
public func localUnreadIndicatorState(engine: TelegramEngine) -> Signal<LocalUnreadIndicatorState, NoError> {
    return localUnreadIndicatorSettings(engine: engine)
    |> map { settings -> Signal<LocalUnreadIndicatorState, NoError> in
        return engine.messages.unreadPeerAndThreadStates(peerIds: settings.enabledPeers, threadIds: settings.enabledTopics)
        |> map { unreadPeers, topicUnreadStates -> LocalUnreadIndicatorState in
            return LocalUnreadIndicatorState(settings: settings, unreadEnabledPeers: unreadPeers, topicUnreadStates: topicUnreadStates)
        }
    }
    |> switchToLatest
    |> distinctUntilChanged
}
