import Foundation
import Postbox
import SwiftSignalKit

/// Stores hidden message senders locally for one signed-in account.
public struct LocalMessageMuteSettings: Codable, Equatable {
    /// Full peer identifiers of users and bots whose conversation messages are hidden.
    public let mutedPeerIds: Set<PeerId>

    /// Creates an account's local message mute list; an empty list hides nothing.
    public init(mutedPeerIds: Set<PeerId> = []) {
        self.mutedPeerIds = mutedPeerIds
    }

    /// Returns a copy with one sender's local message visibility changed.
    public func withUpdatedPeer(peerId: PeerId, muted: Bool) -> LocalMessageMuteSettings {
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
public func localMessageMuteSettings(postbox: Postbox) -> Signal<LocalMessageMuteSettings, NoError> {
    return postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.localMessageMuteSettings])
    |> map { view in
        return view.values[ApplicationSpecificPreferencesKeys.localMessageMuteSettings]?.get(LocalMessageMuteSettings.self) ?? LocalMessageMuteSettings()
    }
    |> distinctUntilChanged
}

/// Updates local message mute preferences without changing server notification or block settings.
public func updateLocalMessageMuteSettings(postbox: Postbox, peerId: PeerId, muted: Bool) -> Signal<Void, NoError> {
    return postbox.transaction { transaction in
        transaction.updatePreferencesEntry(key: ApplicationSpecificPreferencesKeys.localMessageMuteSettings, { entry in
            let settings = entry?.get(LocalMessageMuteSettings.self) ?? LocalMessageMuteSettings()
            return PreferencesEntry(settings.withUpdatedPeer(peerId: peerId, muted: muted))
        })
    }
}
