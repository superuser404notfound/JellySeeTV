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
    private let accessToken: () -> String?

    init(
        baseURLProvider: @escaping () -> URL?,
        accessTokenProvider: @escaping () -> String? = { nil }
    ) {
        self.baseURL = baseURLProvider
        self.accessToken = accessTokenProvider
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
        // api_key lets servers with "require authentication for
        // images" configured (default on modern Jellyfin) serve
        // these URLs to SwiftUI's AsyncImage — AsyncImage uses the
        // shared URLSession and doesn't carry our Authorization
        // header. Including the token also invalidates the cached
        // URL cleanly when the user switches profiles, so stale
        // 401s from a previous profile's token don't linger.
        if let token = accessToken() {
            queryItems.append("api_key=\(token)")
        }

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

    /// Episode thumbnail: episode's own image first, then series backdrop as fallback
    func episodeThumbnailURL(for item: JellyfinItem, maxWidth: Int = 640) -> URL? {
        // 1. Episode's own primary image (the episode still/screenshot)
        if let tag = item.imageTags?.primary {
            return imageURL(itemID: item.id, imageType: .primary, tag: tag, maxWidth: maxWidth)
        }
        // 2. Episode's own thumb
        if let tag = item.imageTags?.thumb {
            return imageURL(itemID: item.id, imageType: .thumb, tag: tag, maxWidth: maxWidth)
        }
        // 3. Episode's own backdrop
        if let tags = item.backdropImageTags, let tag = tags.first {
            return imageURL(itemID: item.id, imageType: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        // 4. Fallback: series backdrop
        if let tags = item.parentBackdropImageTags, let tag = tags.first, let seriesId = item.seriesId {
            return imageURL(itemID: seriesId, imageType: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        // 5. Last fallback: series poster
        if item.type == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag {
            return imageURL(itemID: seriesId, imageType: .primary, tag: tag, maxWidth: maxWidth)
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

    func personImageURL(personID: String, tag: String?, maxWidth: Int = 200) -> URL? {
        guard let base = baseURL(), let tag else { return nil }
        var url = "\(base)/Items/\(personID)/Images/Primary?tag=\(tag)&maxWidth=\(maxWidth)&quality=90"
        if let token = accessToken() { url += "&api_key=\(token)" }
        return URL(string: url)
    }

    /// User avatar (`/Users/{id}/Images/Primary`). Differs from
    /// `imageURL(itemID:…)` in the URL prefix — items live under
    /// `/Items`, users under `/Users`. Returns nil when the user has
    /// no profile picture set so the UI can fall back to initials.
    func userProfileImageURL(userID: String, tag: String?, maxWidth: Int = 240) -> URL? {
        guard let base = baseURL(), let tag else { return nil }
        var url = "\(base)/Users/\(userID)/Images/Primary?tag=\(tag)&maxWidth=\(maxWidth)&quality=90"
        if let token = accessToken() { url += "&api_key=\(token)" }
        return URL(string: url)
    }

    func studioLogoURL(studioName: String, maxWidth: Int = 400) -> URL? {
        guard let base = baseURL() else { return nil }
        let encoded = studioName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? studioName
        var url = "\(base)/Studios/\(encoded)/Images/Primary?maxWidth=\(maxWidth)&quality=90"
        if let token = accessToken() { url += "&api_key=\(token)" }
        return URL(string: url)
    }
}
