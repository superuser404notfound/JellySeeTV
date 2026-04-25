import Foundation

protocol SeerrMediaServiceProtocol: Sendable {
    func movieDetail(tmdbID: Int) async throws -> SeerrMovieDetail
    func tvDetail(tmdbID: Int) async throws -> SeerrTVDetail
    func tvSeasonDetail(tmdbID: Int, seasonNumber: Int) async throws -> SeerrSeasonDetail
}

@MainActor
final class SeerrMediaService: SeerrMediaServiceProtocol {
    private let client: SeerrClient

    init(client: SeerrClient) {
        self.client = client
    }

    func movieDetail(tmdbID: Int) async throws -> SeerrMovieDetail {
        try await client.request(
            endpoint: SeerrEndpoint.movieDetail(tmdbID: tmdbID),
            responseType: SeerrMovieDetail.self
        )
    }

    func tvDetail(tmdbID: Int) async throws -> SeerrTVDetail {
        try await client.request(
            endpoint: SeerrEndpoint.tvDetail(tmdbID: tmdbID),
            responseType: SeerrTVDetail.self
        )
    }

    func tvSeasonDetail(tmdbID: Int, seasonNumber: Int) async throws -> SeerrSeasonDetail {
        try await client.request(
            endpoint: SeerrEndpoint.tvSeasonDetail(tmdbID: tmdbID, seasonNumber: seasonNumber),
            responseType: SeerrSeasonDetail.self
        )
    }
}
