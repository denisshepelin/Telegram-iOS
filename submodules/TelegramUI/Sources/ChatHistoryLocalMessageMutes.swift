import ChatHistoryEntry
import TelegramCore
import TelegramUIPreferences

/// Marks presentation entries by sender, leaving original messages and forward origins intact.
func chatHistoryEntriesWithLocalMessageMutes(_ entries: [ChatHistoryEntry], settings: LocalMessageMuteSettings, revealedMessageIds: Set<EngineMessage.Id>) -> [ChatHistoryEntry] {
    func muteAttributes(message: EngineRawMessage, attributes: ChatMessageEntryAttributes) -> ChatMessageEntryAttributes {
        var attributes = attributes
        attributes.isLocallyMuted = message.author.map { settings.mutedPeerIds.contains($0.id) } == true
            && !revealedMessageIds.contains(message.id)
            && !message.media.contains(where: { $0 is TelegramMediaAction })
        return attributes
    }

    return entries.map { entry in
        switch entry {
        case let .MessageEntry(message, presentationData, read, location, selection, attributes):
            return .MessageEntry(message, presentationData, read, location, selection, muteAttributes(message: message, attributes: attributes))
        case let .MessageGroupEntry(groupId, messages, presentationData):
            return .MessageGroupEntry(groupId, messages.map { message, read, selection, attributes, location in
                return (message, read, selection, muteAttributes(message: message, attributes: attributes), location)
            }, presentationData)
        default:
            return entry
        }
    }
}
