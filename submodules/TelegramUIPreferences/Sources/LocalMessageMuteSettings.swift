import Foundation
import TelegramCore
import SwiftSignalKit

/// Stores hidden message senders locally for one signed-in account.
public struct LocalMessageMuteSettings: Codable, Equatable {
    /// Full peer identifiers of users and bots whose conversation messages are hidden.
    public let mutedPeerIds: Set<EnginePeer.Id>

    /// Creates an account's local message mute list; an empty list hides nothing.
    public init(mutedPeerIds: Set<EnginePeer.Id> = []) {
        self.mutedPeerIds = mutedPeerIds
    }

    /// Returns a copy with one sender's local message visibility changed.
    public func withUpdatedPeer(peerId: EnginePeer.Id, muted: Bool) -> LocalMessageMuteSettings {
        var peerIds = self.mutedPeerIds
        if muted {
            peerIds.insert(peerId)
        } else {
            peerIds.remove(peerId)
        }
        return LocalMessageMuteSettings(mutedPeerIds: peerIds)
    }
}

/// Observes the account's local message mute list without contacting Telegram.
public func localMessageMuteSettings(engine: TelegramEngine) -> Signal<LocalMessageMuteSettings, NoError> {
    return engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.localMessageMuteSettings))
    |> map { entry in
        return entry?.get(LocalMessageMuteSettings.self) ?? LocalMessageMuteSettings()
    }
    |> distinctUntilChanged
}

/// Updates local message mute preferences without changing server notification or block settings.
public func updateLocalMessageMuteSettings(engine: TelegramEngine, peerId: EnginePeer.Id, muted: Bool) -> Signal<Never, NoError> {
    return engine.preferences.update(id: ApplicationSpecificPreferencesKeys.localMessageMuteSettings, { entry in
        let settings = entry?.get(LocalMessageMuteSettings.self) ?? LocalMessageMuteSettings()
        return EnginePreferencesEntry(settings.withUpdatedPeer(peerId: peerId, muted: muted))
    })
}
