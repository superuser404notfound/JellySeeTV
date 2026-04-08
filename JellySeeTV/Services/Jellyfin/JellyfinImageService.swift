import Foundation

enum ImageType: String, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case thumb = "Thumb"
    case logo = "Logo"
    case banner = "Banner"
}

final class JellyfinImageService {
    private let baseURL: () -> URL?

    init(baseURLProvider: @escaping () -> URL?) {
        self.baseURL = baseURLProvider
    }

    func imageURL(
        itemID: String,
        imageType: ImageType = .primary,
        tag: String? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil
    ) -> URL? {
        guard let base = baseURL() else { return nil }

        var path = "\(base)/Items/\(itemID)/Images/\(imageType.rawValue)"

        var queryItems: [String] = []
        if let tag { queryItems.append("tag=\(tag)") }
        if let maxWidth { queryItems.append("maxWidth=\(maxWidth)") }
        if let maxHeight { queryItems.append("maxHeight=\(maxHeight)") }
        queryItems.append("quality=90")

        if !queryItems.isEmpty {
            path += "?" + queryItems.joined(separator: "&")
        }

        return URL(string: path)
    }

    func backdropURL(for item: JellyfinItem, maxWidth: Int = 1920) -> URL? {
        if let tags = item.backdropImageTags, let tag = tags.first {
            return imageURL(itemID: item.id, imageType: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        if let tags = item.parentBackdropImageTags, let tag = tags.first, let seriesId = item.seriesId {
            return imageURL(itemID: seriesId, imageType: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        return nil
    }

    func posterURL(for item: JellyfinItem, maxWidth: Int = 400) -> URL? {
        if let tag = item.imageTags?.primary {
            return imageURL(itemID: item.id, imageType: .primary, tag: tag, maxWidth: maxWidth)
        }
        // For episodes, fall back to series poster
        if item.type == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag {
            return imageURL(itemID: seriesId, imageType: .primary, tag: tag, maxWidth: maxWidth)
        }
        return nil
    }
}
