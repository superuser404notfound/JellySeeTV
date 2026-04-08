import Foundation

protocol JellyfinLibraryServiceProtocol: Sendable {
    func getLibraries(userID: String) async throws -> [JellyfinLibrary]
    func getItems(userID: String, query: ItemQuery) async throws -> JellyfinItemsResponse
    func getResumeItems(userID: String, mediaType: String, limit: Int) async throws -> JellyfinItemsResponse
    func getNextUp(userID: String, seriesID: String?, limit: Int) async throws -> JellyfinItemsResponse
    func getLatestMedia(userID: String, parentID: String?, limit: Int) async throws -> [JellyfinItem]
    func getGenres(userID: String) async throws -> [NamedItem]
    func getStudios(userID: String) async throws -> [NamedItem]
}

final class JellyfinLibraryService: JellyfinLibraryServiceProtocol {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func getLibraries(userID: String) async throws -> [JellyfinLibrary] {
        let response: JellyfinItemsResponse = try await client.request(
            endpoint: JellyfinEndpoint.userViews(userID: userID),
            responseType: JellyfinItemsResponse.self
        )
        // Map items to libraries
        return response.items.map { item in
            JellyfinLibrary(
                id: item.id,
                name: item.name,
                collectionType: item.collectionType,
                imageTags: item.imageTags
            )
        }
    }

    func getItems(userID: String, query: ItemQuery) async throws -> JellyfinItemsResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.items(userID: userID, query: query),
            responseType: JellyfinItemsResponse.self
        )
    }

    func getResumeItems(userID: String, mediaType: String, limit: Int) async throws -> JellyfinItemsResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.resumeItems(userID: userID, mediaType: mediaType, limit: limit),
            responseType: JellyfinItemsResponse.self
        )
    }

    func getNextUp(userID: String, seriesID: String?, limit: Int) async throws -> JellyfinItemsResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.nextUp(userID: userID, seriesID: seriesID, limit: limit),
            responseType: JellyfinItemsResponse.self
        )
    }

    func getLatestMedia(userID: String, parentID: String?, limit: Int) async throws -> [JellyfinItem] {
        try await client.request(
            endpoint: JellyfinEndpoint.latestMedia(userID: userID, parentID: parentID, limit: limit),
            responseType: [JellyfinItem].self
        )
    }

    func getGenres(userID: String) async throws -> [NamedItem] {
        let response: NamedItemsResponse = try await client.request(
            endpoint: JellyfinEndpoint.genres(userID: userID),
            responseType: NamedItemsResponse.self
        )
        return response.items
    }

    func getStudios(userID: String) async throws -> [NamedItem] {
        let response: NamedItemsResponse = try await client.request(
            endpoint: JellyfinEndpoint.studios(userID: userID),
            responseType: NamedItemsResponse.self
        )
        return response.items
    }
}
