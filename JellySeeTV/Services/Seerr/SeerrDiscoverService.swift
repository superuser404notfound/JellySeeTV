import Foundation

protocol SeerrDiscoverServiceProtocol: Sendable {
    func trending(page: Int) async throws -> SeerrDiscoverResult
    func popularMovies(page: Int) async throws -> SeerrDiscoverResult
    func popularTV(page: Int) async throws -> SeerrDiscoverResult
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
}
