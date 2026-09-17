import ChatHistoryEntry
import ChatMessageItem
import TelegramCore

/// Builds disposable rendering copies for muted messages; history retains the original content.
func chatMessageMutedContent(_ content: ChatMessageItemContent, placeholder: String) -> ChatMessageItemContent {
    func mutedMessage(_ message: EngineRawMessage) -> EngineRawMessage {
        return message.withUpdatedText(placeholder)
            .withUpdatedMedia([])
            .withUpdatedAttributes([TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: 0 ..< placeholder.utf16.count, type: .Italic)])])
            .withUpdatedForwardInfo(nil)
    }
    func mutedAttributes(_ attributes: ChatMessageEntryAttributes) -> ChatMessageEntryAttributes {
        var attributes = attributes
        attributes.contentTypeHint = .generic
        attributes.updatingMedia = nil
        attributes.isPlaying = false
        return attributes
    }

    switch content {
    case let .message(message, read, selection, attributes, location):
        guard attributes.isLocallyMuted else {
            return content
        }
        return .message(message: mutedMessage(message), read: read, selection: selection, attributes: mutedAttributes(attributes), location: location)
    case let .group(messages):
        return .group(messages: messages.map { message, read, selection, attributes, location in
            guard attributes.isLocallyMuted else {
                return (message, read, selection, attributes, location)
            }
            return (mutedMessage(message), read, selection, mutedAttributes(attributes), location)
        })
    }
}
