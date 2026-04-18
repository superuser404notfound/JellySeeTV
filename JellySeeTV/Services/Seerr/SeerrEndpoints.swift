import Foundation

enum SeerrEndpoint: APIEndpoint {
    case status
    case authJellyfin(body: SeerrJellyfinAuthBody)
    case authMe
    case authLogout

    case discoverTrending(page: Int)
    case discoverMovies(page: Int)
    case discoverTV(page: Int)

    case movieDetail(tmdbID: Int)
    case tvDetail(tmdbID: Int)

    case createRequest(body: SeerrCreateRequestBody)
    case myRequests(take: Int, skip: Int)

    var path: String {
        switch self {
        case .status: "/api/v1/status"
        case .authJellyfin: "/api/v1/auth/jellyfin"
        case .authMe: "/api/v1/auth/me"
        case .authLogout: "/api/v1/auth/logout"
        case .discoverTrending: "/api/v1/discover/trending"
        case .discoverMovies: "/api/v1/discover/movies"
        case .discoverTV: "/api/v1/discover/tv"
        case .movieDetail(let id): "/api/v1/movie/\(id)"
        case .tvDetail(let id): "/api/v1/tv/\(id)"
        case .createRequest: "/api/v1/request"
        case .myRequests: "/api/v1/request"
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
        case .discoverTrending(let page), .discoverMovies(let page), .discoverTV(let page):
            return [URLQueryItem(name: "page", value: String(page))]

        case .myRequests(let take, let skip):
            return [
                URLQueryItem(name: "take", value: String(take)),
                URLQueryItem(name: "skip", value: String(skip)),
                URLQueryItem(name: "filter", value: "all"),
                URLQueryItem(name: "sort", value: "added"),
                URLQueryItem(name: "requestedBy", value: "me"),
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
