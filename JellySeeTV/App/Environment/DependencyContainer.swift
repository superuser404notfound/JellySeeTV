import Foundation

@MainActor
@Observable
final class DependencyContainer {
    let keychainService: KeychainServiceProtocol
    let httpClient: HTTPClientProtocol
    let jellyfinClient: JellyfinClient
    let serverDiscoveryService: ServerDiscoveryServiceProtocol
    let jellyfinAuthService: JellyfinAuthServiceProtocol
    let jellyfinLibraryService: JellyfinLibraryServiceProtocol
    let jellyfinItemService: JellyfinItemServiceProtocol
    let jellyfinSearchService: JellyfinSearchServiceProtocol
    let jellyfinImageService: JellyfinImageService
    let cloudSyncService: CloudSyncServiceProtocol

    init(
        keychainService: KeychainServiceProtocol = KeychainService(),
        httpClient: HTTPClientProtocol = HTTPClient()
    ) {
        self.keychainService = keychainService
        self.httpClient = httpClient
        self.jellyfinClient = JellyfinClient(httpClient: httpClient)
        self.serverDiscoveryService = ServerDiscoveryService(httpClient: httpClient)
        self.jellyfinAuthService = JellyfinAuthService(client: jellyfinClient)
        self.jellyfinLibraryService = JellyfinLibraryService(client: jellyfinClient)
        self.jellyfinItemService = JellyfinItemService(client: jellyfinClient)
        self.jellyfinSearchService = JellyfinSearchService(client: jellyfinClient)
        self.jellyfinImageService = JellyfinImageService(baseURLProvider: { [weak jellyfinClient] in
            jellyfinClient?.baseURL
        })
        self.cloudSyncService = CloudSyncService()
    }

    func restoreSession() -> Bool {
        guard let serverData = try? keychainService.loadData(for: "activeServer"),
              let server = try? JSONDecoder().decode(JellyfinServer.self, from: serverData),
              let token = try? keychainService.loadString(for: KeychainKeys.accessToken(serverID: server.id))
        else {
            return false
        }

        jellyfinClient.baseURL = server.url
        jellyfinClient.accessToken = token
        return true
    }

    func saveSession(server: JellyfinServer, user: JellyfinUser, token: String) throws {
        let serverData = try JSONEncoder().encode(server)
        try keychainService.save(serverData, for: "activeServer")
        try keychainService.save(token, for: KeychainKeys.accessToken(serverID: server.id))
        try keychainService.save(user.id, for: KeychainKeys.userID(serverID: server.id))
        try keychainService.save(user.name, for: "activeUserName")

        jellyfinClient.baseURL = server.url
        jellyfinClient.accessToken = token
    }

    func clearSession() throws {
        if let server = try? keychainService.loadData(for: "activeServer"),
           let decoded = try? JSONDecoder().decode(JellyfinServer.self, from: server) {
            try keychainService.delete(for: KeychainKeys.accessToken(serverID: decoded.id))
        }
        try keychainService.delete(for: "activeServer")

        jellyfinClient.baseURL = nil
        jellyfinClient.accessToken = nil
    }
}
