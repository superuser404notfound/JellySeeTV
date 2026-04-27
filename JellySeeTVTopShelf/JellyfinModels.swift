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
    /// prefer their own still, falling back to the parent series
    /// backdrop so unscanned episodes don't render as a grey card.
    /// Movies use their backdrop directly.
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
    /// the tight extension memory budget. Cap width at 640 — TopShelf
    /// cells render around 410pt wide on tvOS, anything larger is
    /// just memory waste that can trigger -17102 decompress failures
    /// when several items race to decode at once.
    private func imageURL(baseURL: URL, itemID: String, kind: String, tag: String, token: String) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let raw = "\(base)/Items/\(itemID)/Images/\(kind)?tag=\(tag)&maxWidth=640&quality=85&format=Jpg&api_key=\(token)"
        return URL(string: raw)
    }
}
