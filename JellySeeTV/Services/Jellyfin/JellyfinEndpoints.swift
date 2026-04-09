import Foundation

enum JellyfinEndpoint: APIEndpoint {
    // Server
    case publicInfo

    // Auth
    case authenticateByName(username: String, password: String)

    // Quick Connect
    case quickConnectInitiate
    case quickConnectCheck(secret: String)
    case quickConnectAuthenticate(secret: String)

    // Libraries
    case userViews(userID: String)

    // Items
    case items(userID: String, query: ItemQuery)
    case itemDetail(userID: String, itemID: String)
    case resumeItems(userID: String, mediaType: String, limit: Int)
    case nextUp(userID: String, seriesID: String?, limit: Int)
    case latestMedia(userID: String, parentID: String?, limit: Int)
    case seasons(seriesID: String, userID: String)
    case episodes(seriesID: String, seasonID: String, userID: String)
    case similarItems(itemID: String, userID: String, limit: Int)

    // Genres & Studios
    case genres(userID: String)
    case studios(userID: String)

    // Playback
    case playbackInfo(itemID: String, userID: String)
    case sessionPlaying(report: PlaybackStartReport)
    case sessionProgress(report: PlaybackProgressReport)
    case sessionStopped(report: PlaybackStopReport)

    // Favorites
    case markFavorite(userID: String, itemID: String)
    case unmarkFavorite(userID: String, itemID: String)

    // Search
    case searchHints(userID: String, query: String, limit: Int)

    var path: String {
        switch self {
        case .publicInfo:
            "/System/Info/Public"
        case .authenticateByName:
            "/Users/AuthenticateByName"
        case .quickConnectInitiate:
            "/QuickConnect/Initiate"
        case .quickConnectCheck:
            "/QuickConnect/Connect"
        case .quickConnectAuthenticate:
            "/Users/AuthenticateWithQuickConnect"
        case .userViews(let userID):
            "/Users/\(userID)/Views"
        case .items(let userID, _):
            "/Users/\(userID)/Items"
        case .itemDetail(let userID, let itemID):
            "/Users/\(userID)/Items/\(itemID)"
        case .resumeItems(let userID, _, _):
            "/Users/\(userID)/Items/Resume"
        case .nextUp:
            "/Shows/NextUp"
        case .latestMedia(let userID, _, _):
            "/Users/\(userID)/Items/Latest"
        case .seasons(let seriesID, _):
            "/Shows/\(seriesID)/Seasons"
        case .episodes(let seriesID, _, _):
            "/Shows/\(seriesID)/Episodes"
        case .similarItems(let itemID, _, _):
            "/Items/\(itemID)/Similar"
        case .genres:
            "/Genres"
        case .studios:
            "/Studios"
        case .playbackInfo(let itemID, _):
            "/Items/\(itemID)/PlaybackInfo"
        case .sessionPlaying:
            "/Sessions/Playing"
        case .sessionProgress:
            "/Sessions/Playing/Progress"
        case .sessionStopped:
            "/Sessions/Playing/Stopped"
        case .markFavorite(let userID, let itemID):
            "/Users/\(userID)/FavoriteItems/\(itemID)"
        case .unmarkFavorite(let userID, let itemID):
            "/Users/\(userID)/FavoriteItems/\(itemID)"
        case .searchHints:
            "/Search/Hints"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .authenticateByName, .quickConnectInitiate, .quickConnectAuthenticate, .markFavorite,
             .playbackInfo, .sessionPlaying, .sessionProgress, .sessionStopped:
            .post
        case .unmarkFavorite:
            .delete
        default:
            .get
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .quickConnectCheck(let secret):
            return [URLQueryItem(name: "secret", value: secret)]

        case .items(_, let query):
            return query.toQueryItems()

        case .resumeItems(_, let mediaType, let limit):
            return [
                URLQueryItem(name: "MediaTypes", value: mediaType),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Fields", value: Self.defaultFields),
            ]

        case .nextUp(let userID, let seriesID, let limit):
            var items = [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Fields", value: Self.defaultFields),
            ]
            if let seriesID {
                items.append(URLQueryItem(name: "SeriesId", value: seriesID))
            }
            return items

        case .latestMedia(_, let parentID, let limit):
            var items = [
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Fields", value: Self.defaultFields),
            ]
            if let parentID {
                items.append(URLQueryItem(name: "ParentId", value: parentID))
            }
            return items

        case .seasons(_, let userID):
            return [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Fields", value: Self.defaultFields),
            ]

        case .episodes(_, let seasonID, let userID):
            return [
                URLQueryItem(name: "SeasonId", value: seasonID),
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Fields", value: Self.defaultFields),
            ]

        case .similarItems(_, let userID, let limit):
            return [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Limit", value: String(limit)),
            ]

        case .genres(let userID):
            return [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ]

        case .studios(let userID):
            return [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ]

        case .playbackInfo(_, let userID):
            return [
                URLQueryItem(name: "UserId", value: userID),
            ]

        case .searchHints(let userID, let query, let limit):
            return [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SearchTerm", value: query),
                URLQueryItem(name: "Limit", value: String(limit)),
            ]

        default:
            return nil
        }
    }

    var body: (any Encodable & Sendable)? {
        switch self {
        case .authenticateByName(let username, let password):
            AuthenticateBody(username: username, pw: password)
        case .quickConnectAuthenticate(let secret):
            QuickConnectAuthBody(secret: secret)
        case .playbackInfo:
            PlaybackInfoBody(deviceProfile: DirectPlayProfile.build())
        case .sessionPlaying(let report):
            report
        case .sessionProgress(let report):
            report
        case .sessionStopped(let report):
            report
        default:
            nil
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .publicInfo, .authenticateByName, .quickConnectInitiate, .quickConnectCheck:
            false
        default:
            true
        }
    }

    static let defaultFields = "Overview,Genres,People,Studios,MediaStreams,MediaSources,CommunityRating,OfficialRating,ImageTags,BackdropImageTags,ParentBackdropImageTags,SeriesPrimaryImageTag"
}

struct ItemQuery: Sendable {
    var parentID: String?
    var includeItemTypes: [ItemType]?
    var sortBy: String?
    var sortOrder: String?
    var limit: Int?
    var startIndex: Int?
    var searchTerm: String?
    var genres: [String]?
    var studioNames: [String]?
    var isFavorite: Bool?
    var fields: String?

    func toQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let parentID { items.append(URLQueryItem(name: "ParentId", value: parentID)) }
        if let types = includeItemTypes {
            items.append(URLQueryItem(name: "IncludeItemTypes", value: types.map(\.rawValue).joined(separator: ",")))
        }
        if let sortBy { items.append(URLQueryItem(name: "SortBy", value: sortBy)) }
        if let sortOrder { items.append(URLQueryItem(name: "SortOrder", value: sortOrder)) }
        if let limit { items.append(URLQueryItem(name: "Limit", value: String(limit))) }
        if let startIndex { items.append(URLQueryItem(name: "StartIndex", value: String(startIndex))) }
        if let searchTerm { items.append(URLQueryItem(name: "SearchTerm", value: searchTerm)) }
        if let genres {
            items.append(URLQueryItem(name: "Genres", value: genres.joined(separator: "|")))
        }
        if let studioNames {
            items.append(URLQueryItem(name: "Studios", value: studioNames.joined(separator: "|")))
        }
        if let isFavorite { items.append(URLQueryItem(name: "IsFavorite", value: String(isFavorite))) }

        let fields = fields ?? JellyfinEndpoint.defaultFields
        items.append(URLQueryItem(name: "Fields", value: fields))
        items.append(URLQueryItem(name: "Recursive", value: "true"))

        return items
    }
}

private struct AuthenticateBody: Encodable, Sendable {
    let username: String
    let pw: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case pw = "Pw"
    }
}

private struct QuickConnectAuthBody: Encodable, Sendable {
    let secret: String

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
    }
}

private struct PlaybackInfoBody: Encodable, Sendable {
    let deviceProfile: [String: Any]

    enum CodingKeys: String, CodingKey {
        case deviceProfile = "DeviceProfile"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let data = try JSONSerialization.data(withJSONObject: deviceProfile)
        let json = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        try container.encode(json, forKey: .deviceProfile)
    }
}

/// Helper to encode arbitrary JSON dictionaries
private enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([AnyCodableValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: AnyCodableValue].self) { self = .dictionary(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
