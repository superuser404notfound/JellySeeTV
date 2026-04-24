import Foundation

enum JellyfinEndpoint: APIEndpoint {
    // Server
    case publicInfo
    case publicUsers

    // Auth
    case authenticateByName(username: String, password: String)
    case userDetail(userID: String)
    case currentUser

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
    case latestMedia(userID: String, parentID: String?, includeItemTypes: [ItemType]?, limit: Int)
    case seasons(seriesID: String, userID: String)
    case episodes(seriesID: String, seasonID: String, userID: String)
    case similarItems(itemID: String, userID: String, limit: Int)
    case localTrailers(itemID: String)

    // Genres & Studios
    case genres(userID: String)
    case studios(userID: String)

    // Playback (playbackInfo handled directly in PlaybackService)
    case sessionPlaying(report: PlaybackStartReport)
    case sessionProgress(report: PlaybackProgressReport)
    case sessionStopped(report: PlaybackStopReport)

    // Favorites
    case markFavorite(userID: String, itemID: String)
    case unmarkFavorite(userID: String, itemID: String)

    // Search
    case searchHints(userID: String, query: String, limit: Int)

    // Media Segments (Intro / Outro markers — Jellyfin 10.10+ native,
    // or intro-skipper plugin on older servers)
    case mediaSegments(itemID: String)

    var path: String {
        switch self {
        case .publicInfo:
            "/System/Info/Public"
        case .publicUsers:
            "/Users/Public"
        case .authenticateByName:
            "/Users/AuthenticateByName"
        case .userDetail(let userID):
            "/Users/\(userID)"
        case .currentUser:
            "/Users/Me"
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
        case .latestMedia(let userID, _, _, _):
            "/Users/\(userID)/Items/Latest"
        case .seasons(let seriesID, _):
            "/Shows/\(seriesID)/Seasons"
        case .episodes(let seriesID, _, _):
            "/Shows/\(seriesID)/Episodes"
        case .similarItems(let itemID, _, _):
            "/Items/\(itemID)/Similar"
        case .localTrailers(let itemID):
            "/Items/\(itemID)/LocalTrailers"
        case .genres:
            "/Genres"
        case .studios:
            "/Studios"
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
        case .mediaSegments(let itemID):
            "/MediaSegments/\(itemID)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .authenticateByName, .quickConnectInitiate, .quickConnectAuthenticate, .markFavorite,
             .sessionPlaying, .sessionProgress, .sessionStopped:
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

        case .itemDetail:
            // /Users/{id}/Items/{id} otherwise omits the extended
            // `Fields` (including RemoteTrailers, which the Trailer
            // button needs to resolve YouTube URLs for a detail
            // item). defaultFields is our standard "give me enough
            // to render a rich detail view" set.
            return [URLQueryItem(name: "Fields", value: Self.defaultFields)]

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

        case .latestMedia(_, let parentID, let includeItemTypes, let limit):
            var items = [
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Fields", value: Self.defaultFields),
            ]
            if let parentID {
                items.append(URLQueryItem(name: "ParentId", value: parentID))
            }
            if let includeItemTypes {
                // Filter /Items/Latest to one specific item type —
                // without it, dropping ParentId means the row
                // aggregates movies + series + music in a random
                // jumble instead of feeding a typed "Latest Movies"
                // or "Latest Shows" row.
                items.append(URLQueryItem(
                    name: "IncludeItemTypes",
                    value: includeItemTypes.map(\.rawValue).joined(separator: ",")
                ))
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

        case .searchHints(let userID, let query, let limit):
            return [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SearchTerm", value: query),
                URLQueryItem(name: "Limit", value: String(limit)),
            ]

        case .mediaSegments:
            // Only care about Intro for now; outro would conflict with
            // the next-episode overlay that already covers that window.
            return [URLQueryItem(name: "includeSegmentTypes", value: "Intro")]

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
        case .publicInfo, .publicUsers, .authenticateByName, .quickConnectInitiate, .quickConnectCheck:
            false
        default:
            true
        }
    }

    static let defaultFields = "Overview,Genres,People,Studios,MediaStreams,MediaSources,CommunityRating,OfficialRating,ImageTags,BackdropImageTags,ParentBackdropImageTags,SeriesPrimaryImageTag,ProviderIds,RemoteTrailers"
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
        // Default is true for Movie queries: Jellyfin folds BoxSet
        // members into a single representative row — even when the
        // collection isn't visible in the UI (it may have been created
        // silently from TMDB metadata). Always send false so each movie
        // appears on its own. Our "Collections" row uses a dedicated
        // IncludeItemTypes=BoxSet query and isn't affected.
        items.append(URLQueryItem(name: "CollapseBoxSetItems", value: "false"))

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