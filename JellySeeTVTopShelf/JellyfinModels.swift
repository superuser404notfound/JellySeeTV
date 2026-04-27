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
    /// prefer the parent series Backdrop because Jellyfin's
    /// auto-extracted episode stills are usually 640x360 thumbnails
    /// scraped from the source video — fine in a list, blurry on a
    /// 4K TV card. Series backdrops are curated 1920x1080+ artwork
    /// and match what the native Apple TV app uses for shows.
    /// Episode-specific stills stay in the fallback chain so an
    /// orphan episode (no parent series art) still renders.
    /// Movies use their backdrop directly — same hero-art logic.
    func topShelfImageURL(baseURL: URL, token: String) -> URL? {
        if type == .episode {
            if let seriesId, let tag = parentBackdropImageTags?.first {
                return imageURL(baseURL: baseURL, itemID: seriesId, kind: "Backdrop", tag: tag, token: token)
            }
            if let tag = imageTags?.primary {
                return imageURL(baseURL: baseURL, itemID: id, kind: "Primary", tag: tag, token: token)
            }
            if let tag = imageTags?.thumb {
                return imageURL(baseURL: baseURL, itemID: id, kind: "Thumb", tag: tag, token: token)
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
    /// the tight extension memory budget. 1280px width gives crisp
    /// rendering on Apple TV 4K (cells layout around 410pt = 820px@2x,
    /// with headroom for the focus-zoom animation that scales the
    /// card up by ~1.4x).
    private func imageURL(baseURL: URL, itemID: String, kind: String, tag: String, token: String) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let raw = "\(base)/Items/\(itemID)/Images/\(kind)?tag=\(tag)&maxWidth=1280&quality=90&format=Jpg&api_key=\(token)"
        return URL(string: raw)
    }
}
