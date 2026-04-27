import Foundation

/// Subset of Jellyfin's item DTO the TopShelf actually renders.
/// Mirrors the server's PascalCase keys so the same JSON the main
/// app receives also decodes here without massaging the response.
struct JellyfinItem: Decodable, Sendable {
    let id: String
    let name: String
    let type: ItemType
    let seriesName: String?
    let seriesId: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let imageTags: ImageTags?
    let backdropImageTags: [String]?
    let parentBackdropImageTags: [String]?
    let seriesPrimaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case seriesName = "SeriesName"
        case seriesId = "SeriesId"
        case parentIndexNumber = "ParentIndexNumber"
        case indexNumber = "IndexNumber"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
    }
}

enum ItemType: String, Decodable, Sendable {
    case movie = "Movie"
    case series = "Series"
    case episode = "Episode"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemType(rawValue: raw) ?? .unknown
    }
}

struct ImageTags: Decodable, Sendable {
    let primary: String?
    let backdrop: String?
    let thumb: String?

    enum CodingKeys: String, CodingKey {
        case primary = "Primary"
        case backdrop = "Backdrop"
        case thumb = "Thumb"
    }
}

extension JellyfinItem {
    /// Wide thumbnail for the TopShelf carousel cell. Episodes
    /// prefer their own Primary still so each card shows the actual
    /// scene, with the parent series backdrop as a fallback for the
    /// rare orphan episode that has no scraped thumbnail. Movies use
    /// their backdrop directly.
    ///
    /// Episode resolution depends on the source: Jellyfin extracts
    /// the still at the server's "image extraction width" library
    /// setting (320 in old defaults, 1920 if cranked up) and we can't
    /// upscale that client-side. `imageURL` requests with
    /// `enableImageEnhancers=false` so any server-side enhancer that
    /// downscales doesn't get in the way.
    func topShelfImageURL(baseURL: URL, token: String) -> URL? {
        if type == .episode {
            if let tag = imageTags?.primary {
                return imageURL(baseURL: baseURL, itemID: id, kind: "Primary", tag: tag, token: token)
            }
            if let tag = imageTags?.thumb {
                return imageURL(baseURL: baseURL, itemID: id, kind: "Thumb", tag: tag, token: token)
            }
            if let seriesId, let tag = parentBackdropImageTags?.first {
                return imageURL(baseURL: baseURL, itemID: seriesId, kind: "Backdrop", tag: tag, token: token)
            }
        }
        if let tag = backdropImageTags?.first {
            return imageURL(baseURL: baseURL, itemID: id, kind: "Backdrop", tag: tag, token: token)
        }
        if let tag = imageTags?.primary {
            return imageURL(baseURL: baseURL, itemID: id, kind: "Primary", tag: tag, token: token)
        }
        return nil
    }

    /// Combined headline for the home-screen card. Movies render as
    /// their bare name; episodes prefix the series + S/E breadcrumb
    /// because the still alone doesn't tell you which show it is.
    var topShelfTitle: String {
        guard type == .episode, let series = seriesName else { return name }
        if let s = parentIndexNumber, let e = indexNumber {
            return "\(series) · S\(s)E\(e) · \(name)"
        }
        return "\(series) · \(name)"
    }

    /// Force `format=Jpg` so the system's image-cache daemon never
    /// sees a WebP/AVIF response that ImageIO might choke on inside
    /// the tight extension memory budget. 1280px cap is enough for
    /// Apple TV 4K (cells layout around 820px@2x with focus-zoom
    /// headroom). `enableImageEnhancers=false` skips any server-side
    /// transform that might downscale before delivery — and quality
    /// is pinned at 100 to avoid stacking JPEG losses on top of an
    /// already-thumbnail-sized episode still.
    private func imageURL(baseURL: URL, itemID: String, kind: String, tag: String, token: String) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let raw = "\(base)/Items/\(itemID)/Images/\(kind)?tag=\(tag)&maxWidth=1280&quality=100&format=Jpg&enableImageEnhancers=false&api_key=\(token)"
        return URL(string: raw)
    }
}
