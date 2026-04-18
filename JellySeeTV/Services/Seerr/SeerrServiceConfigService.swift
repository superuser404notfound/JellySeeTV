import Foundation

protocol SeerrServiceConfigServiceProtocol: Sendable {
    func radarrServers() async throws -> [SeerrServiceServer]
    func radarrDetails(serverID: Int) async throws -> SeerrServiceDetails
    func sonarrServers() async throws -> [SeerrServiceServer]
    func sonarrDetails(serverID: Int) async throws -> SeerrServiceDetails
}

@MainActor
final class SeerrServiceConfigService: SeerrServiceConfigServiceProtocol {
    private let client: SeerrClient

    init(client: SeerrClient) {
        self.client = client
    }

    func radarrServers() async throws -> [SeerrServiceServer] {
        try await client.request(
            endpoint: SeerrEndpoint.radarrServers,
            responseType: [SeerrServiceServer].self
        )
    }

    func radarrDetails(serverID: Int) async throws -> SeerrServiceDetails {
        try await client.request(
            endpoint: SeerrEndpoint.radarrDetails(serverID: serverID),
            responseType: SeerrServiceDetails.self
        )
    }

    func sonarrServers() async throws -> [SeerrServiceServer] {
        try await client.request(
            endpoint: SeerrEndpoint.sonarrServers,
            responseType: [SeerrServiceServer].self
        )
    }

    func sonarrDetails(serverID: Int) async throws -> SeerrServiceDetails {
        try await client.request(
            endpoint: SeerrEndpoint.sonarrDetails(serverID: serverID),
            responseType: SeerrServiceDetails.self
        )
    }
}
