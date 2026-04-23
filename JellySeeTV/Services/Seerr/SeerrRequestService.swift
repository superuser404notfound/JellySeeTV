import Foundation

protocol SeerrRequestServiceProtocol: Sendable {
    func createRequest(
        mediaType: SeerrMediaType,
        tmdbID: Int,
        seasons: [Int]?,
        serverID: Int?,
        profileID: Int?,
        rootFolder: String?,
        languageProfileID: Int?
    ) async throws -> SeerrRequest
    func myRequests(userID: Int, take: Int, skip: Int) async throws -> SeerrRequestsResult
}

@MainActor
final class SeerrRequestService: SeerrRequestServiceProtocol {
    private let client: SeerrClient

    init(client: SeerrClient) {
        self.client = client
    }

    func createRequest(
        mediaType: SeerrMediaType,
        tmdbID: Int,
        seasons: [Int]? = nil,
        serverID: Int? = nil,
        profileID: Int? = nil,
        rootFolder: String? = nil,
        languageProfileID: Int? = nil
    ) async throws -> SeerrRequest {
        let body = SeerrCreateRequestBody(
            mediaType: mediaType,
            mediaId: tmdbID,
            seasons: seasons,
            serverId: serverID,
            profileId: profileID,
            rootFolder: rootFolder,
            languageProfileId: languageProfileID
        )
        return try await client.request(
            endpoint: SeerrEndpoint.createRequest(body: body),
            responseType: SeerrRequest.self
        )
    }

    func myRequests(userID: Int, take: Int = 50, skip: Int = 0) async throws -> SeerrRequestsResult {
        try await client.request(
            endpoint: SeerrEndpoint.myRequests(userID: userID, take: take, skip: skip),
            responseType: SeerrRequestsResult.self
        )
    }
}
