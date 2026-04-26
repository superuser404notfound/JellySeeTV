import Foundation

protocol SeerrDiscoverServiceProtocol: Sendable {
    func trending(page: Int) async throws -> SeerrDiscoverResult
    func popularMovies(page: Int) async throws -> SeerrDiscoverResult
    func popularTV(page: Int) async throws -> SeerrDiscoverResult
    func upcomingMovies(page: Int) async throws -> SeerrDiscoverResult
    func upcomingTV(page: Int) async throws -> SeerrDiscoverResult
    func moviesByGenre(genreID: Int, page: Int) async throws -> SeerrDiscoverResult
    func tvByGenre(genreID: Int, page: Int) async throws -> SeerrDiscoverResult
    func moviesByStudio(studioID: Int, page: Int) async throws -> SeerrDiscoverResult
    func tvByNetwork(networkID: Int, page: Int) async throws -> SeerrDiscoverResult
    func moviesByWatchProvider(providerID: Int, region: String, page: Int) async throws -> SeerrDiscoverResult
    func tvByWatchProvider(providerID: Int, region: String, page: Int) async throws -> SeerrDiscoverResult
    func movieGenres() async throws -> [SeerrGenreSlide]
    func tvGenres() async throws -> [SeerrGenreSlide]
}

@MainActor
final class SeerrDiscoverService: SeerrDiscoverServiceProtocol {
    private let client: SeerrClient

    init(client: SeerrClient) {
        self.client = client
    }

    func trending(page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverTrending(page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func popularMovies(page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverMovies(page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func popularTV(page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverTV(page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func upcomingMovies(page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverUpcomingMovies(page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func upcomingTV(page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverUpcomingTV(page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func moviesByGenre(genreID: Int, page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverMoviesByGenre(genreID: genreID, page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func tvByGenre(genreID: Int, page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverTVByGenre(genreID: genreID, page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func moviesByStudio(studioID: Int, page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverMoviesByStudio(studioID: studioID, page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func tvByNetwork(networkID: Int, page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverTVByNetwork(networkID: networkID, page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func moviesByWatchProvider(providerID: Int, region: String, page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverMoviesByWatchProvider(providerID: providerID, region: region, page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func tvByWatchProvider(providerID: Int, region: String, page: Int = 1) async throws -> SeerrDiscoverResult {
        try await client.request(
            endpoint: SeerrEndpoint.discoverTVByWatchProvider(providerID: providerID, region: region, page: page),
            responseType: SeerrDiscoverResult.self
        )
    }

    func movieGenres() async throws -> [SeerrGenreSlide] {
        try await client.request(
            endpoint: SeerrEndpoint.genresMovie,
            responseType: [SeerrGenreSlide].self
        )
    }

    func tvGenres() async throws -> [SeerrGenreSlide] {
        try await client.request(
            endpoint: SeerrEndpoint.genresTV,
            responseType: [SeerrGenreSlide].self
        )
    }
}
