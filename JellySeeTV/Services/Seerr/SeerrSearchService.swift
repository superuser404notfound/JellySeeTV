import Foundation

protocol SeerrSearchServiceProtocol: Sendable {
    func search(query: String, page: Int) async throws -> SeerrDiscoverResult
}

@MainActor
final class SeerrSearchService: SeerrSearchServiceProtocol {
    private let client: SeerrClient

    init(client: SeerrClient) {
        self.client = client
    }

    func search(query: String, page: Int = 1) async throws -> SeerrDiscoverResult {
        let raw = try await client.request(
            endpoint: SeerrEndpoint.search(query: query, page: page),
            responseType: SeerrDiscoverResult.self
        )
        // Drop `person` results — the catalog only shows requestable
        // media. Re-wrap so pagination metadata stays intact.
        let filtered = raw.results.filter { $0.mediaType != .person }
        return SeerrDiscoverResult(
            page: raw.page,
            totalPages: raw.totalPages,
            totalResults: raw.totalResults,
            results: filtered
        )
    }
}
