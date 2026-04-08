import Foundation

protocol JellyfinItemServiceProtocol: Sendable {
    func getItemDetail(userID: String, itemID: String) async throws -> JellyfinItem
    func getSeasons(seriesID: String, userID: String) async throws -> JellyfinItemsResponse
    func getEpisodes(seriesID: String, seasonID: String, userID: String) async throws -> JellyfinItemsResponse
    func getSimilarItems(itemID: String, userID: String, limit: Int) async throws -> JellyfinItemsResponse
}

final class JellyfinItemService: JellyfinItemServiceProtocol {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func getItemDetail(userID: String, itemID: String) async throws -> JellyfinItem {
        try await client.request(
            endpoint: JellyfinEndpoint.itemDetail(userID: userID, itemID: itemID),
            responseType: JellyfinItem.self
        )
    }

    func getSeasons(seriesID: String, userID: String) async throws -> JellyfinItemsResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.seasons(seriesID: seriesID, userID: userID),
            responseType: JellyfinItemsResponse.self
        )
    }

    func getEpisodes(seriesID: String, seasonID: String, userID: String) async throws -> JellyfinItemsResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.episodes(seriesID: seriesID, seasonID: seasonID, userID: userID),
            responseType: JellyfinItemsResponse.self
        )
    }

    func getSimilarItems(itemID: String, userID: String, limit: Int) async throws -> JellyfinItemsResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.similarItems(itemID: itemID, userID: userID, limit: limit),
            responseType: JellyfinItemsResponse.self
        )
    }
}
