import Foundation

enum SeerrEndpoint: APIEndpoint {
    case status
    case authJellyfin(body: SeerrJellyfinAuthBody)
    case authMe
    case authLogout

    case discoverTrending(page: Int)
    case discoverMovies(page: Int)
    case discoverTV(page: Int)
    case discoverUpcomingMovies(page: Int)
    case discoverUpcomingTV(page: Int)
    case discoverMoviesByGenre(genreID: Int, page: Int)
    case discoverTVByGenre(genreID: Int, page: Int)
    case discoverMoviesByStudio(studioID: Int, page: Int)
    case discoverTVByNetwork(networkID: Int, page: Int)
    case genresMovie
    case genresTV

    case search(query: String, page: Int)

    case movieDetail(tmdbID: Int)
    case tvDetail(tmdbID: Int)
    case tvSeasonDetail(tmdbID: Int, seasonNumber: Int)

    case createRequest(body: SeerrCreateRequestBody)
    case myRequests(userID: Int, take: Int, skip: Int)

    case radarrServers
    case radarrDetails(serverID: Int)
    case sonarrServers
    case sonarrDetails(serverID: Int)

    var path: String {
        switch self {
        case .status: "/api/v1/status"
        case .authJellyfin: "/api/v1/auth/jellyfin"
        case .authMe: "/api/v1/auth/me"
        case .authLogout: "/api/v1/auth/logout"
        case .discoverTrending: "/api/v1/discover/trending"
        case .discoverMovies: "/api/v1/discover/movies"
        case .discoverTV: "/api/v1/discover/tv"
        case .discoverUpcomingMovies: "/api/v1/discover/movies/upcoming"
        case .discoverUpcomingTV: "/api/v1/discover/tv/upcoming"
        case .discoverMoviesByGenre(let genreID, _): "/api/v1/discover/movies/genre/\(genreID)"
        case .discoverTVByGenre(let genreID, _): "/api/v1/discover/tv/genre/\(genreID)"
        case .discoverMoviesByStudio(let studioID, _): "/api/v1/discover/movies/studio/\(studioID)"
        case .discoverTVByNetwork(let networkID, _): "/api/v1/discover/tv/network/\(networkID)"
        case .genresMovie: "/api/v1/discover/genreslider/movie"
        case .genresTV: "/api/v1/discover/genreslider/tv"
        case .search: "/api/v1/search"
        case .movieDetail(let id): "/api/v1/movie/\(id)"
        case .tvDetail(let id): "/api/v1/tv/\(id)"
        case .tvSeasonDetail(let id, let n): "/api/v1/tv/\(id)/season/\(n)"
        case .createRequest: "/api/v1/request"
        case .myRequests: "/api/v1/request"
        case .radarrServers: "/api/v1/service/radarr"
        case .radarrDetails(let id): "/api/v1/service/radarr/\(id)"
        case .sonarrServers: "/api/v1/service/sonarr"
        case .sonarrDetails(let id): "/api/v1/service/sonarr/\(id)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .authJellyfin, .createRequest: .post
        case .authLogout: .post
        default: .get
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .discoverTrending(let page),
             .discoverMovies(let page),
             .discoverTV(let page),
             .discoverUpcomingMovies(let page),
             .discoverUpcomingTV(let page):
            return [URLQueryItem(name: "page", value: String(page))]

        case .discoverMoviesByGenre(_, let page),
             .discoverTVByGenre(_, let page),
             .discoverMoviesByStudio(_, let page),
             .discoverTVByNetwork(_, let page):
            return [URLQueryItem(name: "page", value: String(page))]

        case .search(let query, let page):
            return [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "page", value: String(page)),
            ]

        case .myRequests(let userID, let take, let skip):
            return [
                URLQueryItem(name: "take", value: String(take)),
                URLQueryItem(name: "skip", value: String(skip)),
                URLQueryItem(name: "filter", value: "all"),
                URLQueryItem(name: "sort", value: "added"),
                // Jellyseerr's requestedBy filter compares against an
                // integer user ID directly — "me" was a bad guess that
                // silently matched zero requests on every call.
                URLQueryItem(name: "requestedBy", value: String(userID)),
            ]

        default:
            return nil
        }
    }

    var body: (any Encodable & Sendable)? {
        switch self {
        case .authJellyfin(let body): body
        case .createRequest(let body): body
        default: nil
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .status, .authJellyfin: false
        default: true
        }
    }
}
