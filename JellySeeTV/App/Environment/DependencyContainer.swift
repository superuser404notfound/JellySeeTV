import Foundation
import AetherEngine

@MainActor
@Observable
final class DependencyContainer {
    @MainActor static let playerEngine: AetherEngine = try! AetherEngine()
    let keychainService: KeychainServiceProtocol
    let httpClient: HTTPClientProtocol
    let jellyfinClient: JellyfinClient
    let serverDiscoveryService: ServerDiscoveryServiceProtocol
    let jellyfinAuthService: JellyfinAuthServiceProtocol
    let jellyfinLibraryService: JellyfinLibraryServiceProtocol
    let jellyfinItemService: JellyfinItemServiceProtocol
    let jellyfinSearchService: JellyfinSearchServiceProtocol
    let jellyfinImageService: JellyfinImageService
    let jellyfinPlaybackService: JellyfinPlaybackServiceProtocol
    let cloudSyncService: CloudSyncServiceProtocol
    let playbackPreferences: PlaybackPreferences

    let seerrClient: SeerrClient
    let seerrServerDiscoveryService: SeerrServerDiscoveryServiceProtocol
    let seerrAuthService: SeerrAuthServiceProtocol
    let seerrDiscoverService: SeerrDiscoverServiceProtocol
    let seerrMediaService: SeerrMediaServiceProtocol
    let seerrRequestService: SeerrRequestServiceProtocol
    let seerrServiceConfigService: SeerrServiceConfigServiceProtocol

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
        self.jellyfinPlaybackService = JellyfinPlaybackService(client: jellyfinClient)
        self.cloudSyncService = CloudSyncService()
        self.playbackPreferences = PlaybackPreferences()

        self.seerrClient = SeerrClient(httpClient: httpClient)
        self.seerrServerDiscoveryService = SeerrServerDiscoveryService(httpClient: httpClient)
        self.seerrAuthService = SeerrAuthService(client: seerrClient)
        self.seerrDiscoverService = SeerrDiscoverService(client: seerrClient)
        self.seerrMediaService = SeerrMediaService(client: seerrClient)
        self.seerrRequestService = SeerrRequestService(client: seerrClient)
        self.seerrServiceConfigService = SeerrServiceConfigService(client: seerrClient)
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

    func saveSession(
        server: JellyfinServer,
        user: JellyfinUser,
        token: String,
        password: String? = nil
    ) throws {
        let serverData = try JSONEncoder().encode(server)
        try keychainService.save(serverData, for: "activeServer")
        try keychainService.save(token, for: KeychainKeys.accessToken(serverID: server.id))
        try keychainService.save(user.id, for: KeychainKeys.userID(serverID: server.id))
        try keychainService.save(user.name, for: "activeUserName")

        if let password, !password.isEmpty {
            try keychainService.save(password, for: KeychainKeys.jellyfinPassword(serverID: server.id))
        }

        jellyfinClient.baseURL = server.url
        jellyfinClient.accessToken = token
    }

    func loadJellyfinPassword() -> String? {
        guard let server = activeJellyfinServerID else { return nil }
        return try? keychainService.loadString(for: KeychainKeys.jellyfinPassword(serverID: server))
    }

    private var activeJellyfinServerID: String? {
        guard let data = try? keychainService.loadData(for: "activeServer"),
              let server = try? JSONDecoder().decode(JellyfinServer.self, from: data)
        else { return nil }
        return server.id
    }

    func clearSession() throws {
        if let server = try? keychainService.loadData(for: "activeServer"),
           let decoded = try? JSONDecoder().decode(JellyfinServer.self, from: server) {
            try keychainService.delete(for: KeychainKeys.accessToken(serverID: decoded.id))
            try keychainService.delete(for: KeychainKeys.jellyfinPassword(serverID: decoded.id))
        }
        try keychainService.delete(for: "activeServer")

        jellyfinClient.baseURL = nil
        jellyfinClient.accessToken = nil

        try clearSeerrSession()
    }

    func restoreSeerrSession() -> SeerrServer? {
        guard let serverData = try? keychainService.loadData(for: KeychainKeys.seerrServer),
              let server = try? JSONDecoder().decode(SeerrServer.self, from: serverData),
              let cookie = try? keychainService.loadString(for: KeychainKeys.seerrSession(serverID: server.id))
        else {
            return nil
        }

        seerrClient.baseURL = server.url
        seerrClient.sessionCookie = cookie
        return server
    }

    func saveSeerrSession(server: SeerrServer) throws {
        let serverData = try JSONEncoder().encode(server)
        try keychainService.save(serverData, for: KeychainKeys.seerrServer)
        if let cookie = seerrClient.sessionCookie {
            try keychainService.save(cookie, for: KeychainKeys.seerrSession(serverID: server.id))
        }
        seerrClient.baseURL = server.url
    }

    func clearSeerrSession() throws {
        if let serverData = try? keychainService.loadData(for: KeychainKeys.seerrServer),
           let decoded = try? JSONDecoder().decode(SeerrServer.self, from: serverData) {
            try keychainService.delete(for: KeychainKeys.seerrSession(serverID: decoded.id))
        }
        try keychainService.delete(for: KeychainKeys.seerrServer)

        seerrClient.baseURL = nil
        seerrClient.sessionCookie = nil
    }
}
