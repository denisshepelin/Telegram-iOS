import Foundation
import TelegramCore
import TextFormat

/// Converts a message snapshot to reader blocks without fetching or changing message content.
func messageReaderInstantPage(message: EngineRawMessage) -> InstantPage {
    if let richText = message.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute {
        return richText.instantPage
    }
    let text = message.text as NSString
    let storedEntities = (message.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
    let validEntities = storedEntities.filter { $0.range.lowerBound >= 0 && $0.range.upperBound <= text.length && !$0.range.isEmpty }
    let entities = generateTextEntities(message.text, enabledTypes: [.allUrl, .mention, .phoneNumber], currentEntities: validEntities).compactMap { entity -> MessageTextEntity? in
        guard entity.range.lowerBound >= 0, entity.range.upperBound <= text.length, !entity.range.isEmpty else {
            return nil
        }
        let value = text.substring(with: NSRange(location: entity.range.lowerBound, length: entity.range.count))
        let url: String
        switch entity.type {
        case .Url:
            url = value.contains("://") ? value : "https://" + value
        case .Email:
            url = "mailto:" + value
        case .PhoneNumber:
            url = "tel:" + value
        case .Mention:
            url = "https://t.me/" + value.dropFirst()
        default:
            return entity
        }
        return MessageTextEntity(range: entity.range, type: .TextUrl(url: url))
    }
    let attributedText = chatInputStateStringWithAppliedEntities(message.text, entities: entities)
    return instantPage(from: chatInputContent(from: attributedText))
}

/// Wraps local reader blocks for the Instant View renderer, with no remote webpage identity.
func messageReaderWebpage(instantPage: InstantPage) -> TelegramMediaWebpage {
    return TelegramMediaWebpage(webpageId: EngineMedia.Id(namespace: 0, id: 0), content: .Loaded(TelegramMediaWebpageLoadedContent(
        url: "", displayUrl: "", hash: 0, type: nil, websiteName: nil, title: nil, text: nil,
        embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil,
        isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil,
        attributes: [], instantPage: instantPage
    )))
}
