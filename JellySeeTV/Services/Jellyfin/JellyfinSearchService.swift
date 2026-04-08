import Foundation

struct SearchHintsResponse: Codable, Sendable {
    let searchHints: [SearchHint]
    let totalRecordCount: Int

    enum CodingKeys: String, CodingKey {
        case searchHints = "SearchHints"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct SearchHint: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: ItemType
    let productionYear: Int?
    let primaryImageTag: String?
    let seriesName: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case productionYear = "ProductionYear"
        case primaryImageTag = "PrimaryImageTag"
        case seriesName = "SeriesName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
    }
}

protocol JellyfinSearchServiceProtocol: Sendable {
    func search(userID: String, query: String, limit: Int) async throws -> SearchHintsResponse
}

final class JellyfinSearchService: JellyfinSearchServiceProtocol {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func search(userID: String, query: String, limit: Int) async throws -> SearchHintsResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.searchHints(userID: userID, query: query, limit: limit),
            responseType: SearchHintsResponse.self
        )
    }
}
