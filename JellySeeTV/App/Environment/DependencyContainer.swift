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
    let storeKitService: StoreKitServiceProtocol
    let appearancePreferences: AppearancePreferences
    let authPreferences: AuthPreferences

    let seerrClient: SeerrClient
    let seerrServerDiscoveryService: SeerrServerDiscoveryServiceProtocol
    let seerrAuthService: SeerrAuthServiceProtocol
    let seerrDiscoverService: SeerrDiscoverServiceProtocol
    let seerrMediaService: SeerrMediaServiceProtocol
    let seerrRequestService: SeerrRequestServiceProtocol
    let seerrServiceConfigService: SeerrServiceConfigServiceProtocol
    let seerrSearchService: SeerrSearchServiceProtocol

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
        self.jellyfinImageService = JellyfinImageService(
            baseURLProvider: { [weak jellyfinClient] in
                jellyfinClient?.baseURL
            },
            accessTokenProvider: { [weak jellyfinClient] in
                jellyfinClient?.accessToken
            }
        )
        self.jellyfinPlaybackService = JellyfinPlaybackService(client: jellyfinClient)
        self.cloudSyncService = CloudSyncService()
        self.playbackPreferences = PlaybackPreferences()
        self.storeKitService = StoreKitService()
        self.appearancePreferences = AppearancePreferences()
        self.authPreferences = AuthPreferences()

        self.seerrClient = SeerrClient(httpClient: httpClient)
        self.seerrServerDiscoveryService = SeerrServerDiscoveryService(httpClient: httpClient)
        self.seerrAuthService = SeerrAuthService(client: seerrClient)
        self.seerrDiscoverService = SeerrDiscoverService(client: seerrClient)
        self.seerrMediaService = SeerrMediaService(client: seerrClient)
        self.seerrRequestService = SeerrRequestService(client: seerrClient)
        self.seerrServiceConfigService = SeerrServiceConfigService(client: seerrClient)
        self.seerrSearchService = SeerrSearchService(client: seerrClient)
    }

    /// `try?` is intentional here: a missing or unreadable Keychain entry
    /// (fresh install, wiped storage, corrupted item) means there's no session
    /// to restore — the app falls back to the login screen. There's no recovery
    /// path that would benefit from inspecting the underlying error.
    func restoreSession() -> Bool {
        guard let serverData = try? keychainService.loadData(for: "activeServer"),
              let server = try? JSONDecoder().decode(JellyfinServer.self, from: serverData),
              let token = try? keychainService.loadString(for: KeychainKeys.accessToken(serverID: server.id))
        else {
            return false
        }

        jellyfinClient.baseURL = server.url
        jellyfinClient.accessToken = token

        // Re-project into the shared keychain on every cold launch
        // so the TopShelf extension stays in lockstep even if a
        // previous app version didn't write the mirror, or the user
        // wiped just the shelf's bucket somehow.
        if let userID = try? keychainService.loadString(for: KeychainKeys.userID(serverID: server.id)) {
            SharedSessionMirror.write(serverURL: server.url, userID: userID, accessToken: token)
        }
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

        // Persist the avatar image tag so Settings can render the
        // profile picture across cold launches instead of falling
        // back to initials. If the user has no custom avatar, clear
        // any previously-stored tag so a removed image doesn't
        // linger and 404 on every restore.
        if let tag = user.primaryImageTag, !tag.isEmpty {
            try keychainService.save(tag, for: "activeUserImageTag")
        } else {
            try? keychainService.delete(for: "activeUserImageTag")
        }

        if let password, !password.isEmpty {
            try keychainService.save(password, for: KeychainKeys.jellyfinPassword(serverID: server.id))
        }

        jellyfinClient.baseURL = server.url
        jellyfinClient.accessToken = token

        SharedSessionMirror.write(serverURL: server.url, userID: user.id, accessToken: token)

        // Add/update this user in the remembered-profiles list for
        // the server so the user can later switch to any previous
        // profile without re-authenticating.
        try rememberUser(
            RememberedUser(
                id: user.id,
                serverID: server.id,
                name: user.name,
                imageTag: user.primaryImageTag,
                token: token
            )
        )
    }

    // MARK: - Remembered Profiles

    /// All profiles for a server whose token we have cached. Sorted
    /// by most-recently-added first so fresh logins float to the top
    /// of pickers.
    func listRememberedUsers(serverID: String) -> [RememberedUser] {
        guard let data = try? keychainService.loadData(
            for: KeychainKeys.rememberedUsers(serverID: serverID)
        ) else { return [] }
        let users = (try? JSONDecoder().decode([RememberedUser].self, from: data)) ?? []
        return users.sorted { $0.addedAt > $1.addedAt }
    }

    /// Upsert — replaces any existing entry with the same user ID so
    /// re-logins refresh the token and avatar tag instead of
    /// stacking duplicates.
    func rememberUser(_ user: RememberedUser) throws {
        var users = listRememberedUsers(serverID: user.serverID)
            .filter { $0.id != user.id }
        users.append(user)
        let data = try JSONEncoder().encode(users)
        try keychainService.save(
            data,
            for: KeychainKeys.rememberedUsers(serverID: user.serverID)
        )
    }

    /// Drop one profile from the remembered list. Called from the
    /// profile-picker's long-press menu. Leaves the active session
    /// alone — the caller decides whether to switch afterwards.
    func forgetUser(id: String, serverID: String) throws {
        let remaining = listRememberedUsers(serverID: serverID)
            .filter { $0.id != id }
        if remaining.isEmpty {
            try? keychainService.delete(
                for: KeychainKeys.rememberedUsers(serverID: serverID)
            )
        } else {
            let data = try JSONEncoder().encode(remaining)
            try keychainService.save(
                data,
                for: KeychainKeys.rememberedUsers(serverID: serverID)
            )
        }
        // Drop the profile-scoped Seerr session too so a forgotten
        // user doesn't leave a dangling Seerr cookie in the keychain.
        forgetRememberedSeerr(forJellyfinUserID: id, jellyfinServerID: serverID)
    }

    /// Swap to an already-remembered profile. Re-uses the cached
    /// token, updates the active-session keychain entries, and
    /// reconfigures the HTTP client. Drops the cached Jellyfin
    /// password (which is keyed per-server, not per-user) so the
    /// Seerr auto-fill doesn't pre-fill the previous user's
    /// password onto the new user.
    func switchToUser(_ remembered: RememberedUser, server: JellyfinServer) throws {
        let serverData = try JSONEncoder().encode(server)
        try keychainService.save(serverData, for: "activeServer")
        try keychainService.save(
            remembered.token,
            for: KeychainKeys.accessToken(serverID: server.id)
        )
        try keychainService.save(
            remembered.id,
            for: KeychainKeys.userID(serverID: server.id)
        )
        try keychainService.save(remembered.name, for: "activeUserName")

        if let tag = remembered.imageTag, !tag.isEmpty {
            try keychainService.save(tag, for: "activeUserImageTag")
        } else {
            try? keychainService.delete(for: "activeUserImageTag")
        }

        try? keychainService.delete(for: KeychainKeys.jellyfinPassword(serverID: server.id))

        jellyfinClient.baseURL = server.url
        jellyfinClient.accessToken = remembered.token

        SharedSessionMirror.write(
            serverURL: server.url,
            userID: remembered.id,
            accessToken: remembered.token
        )

        // Seerr is handled separately by the caller via
        // restoreSeerrSession(forJellyfinUserID:jellyfinServerID:).
        // Keeping it out of switchToUser means a profile that has
        // its own remembered Seerr session picks it back up on
        // switch, while a profile with no Seerr history correctly
        // lands on the "set up Seerr" empty state.
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
            // Before we forget the remembered profile list, tear
            // down every profile's per-user Seerr session — otherwise
            // they linger in the keychain as orphaned blobs.
            for remembered in listRememberedUsers(serverID: decoded.id) {
                forgetRememberedSeerr(
                    forJellyfinUserID: remembered.id,
                    jellyfinServerID: decoded.id
                )
            }
            // Full logout = nuke every remembered profile for this
            // server too. Profile pruning at a finer granularity
            // happens via forgetUser() from the picker's long-press
            // menu.
            try? keychainService.delete(
                for: KeychainKeys.rememberedUsers(serverID: decoded.id)
            )
        }
        try keychainService.delete(for: "activeServer")
        try? keychainService.delete(for: "activeUserImageTag")

        jellyfinClient.baseURL = nil
        jellyfinClient.accessToken = nil

        SharedSessionMirror.clear()

        try clearSeerrSession()
    }

    /// See `restoreSession()` for the rationale behind silent `try?` here.
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

    func saveSeerrSession(
        server: SeerrServer,
        forJellyfinUserID jellyfinUserID: String? = nil,
        jellyfinServerID: String? = nil
    ) throws {
        let serverData = try JSONEncoder().encode(server)
        try keychainService.save(serverData, for: KeychainKeys.seerrServer)
        if let cookie = seerrClient.sessionCookie {
            try keychainService.save(cookie, for: KeychainKeys.seerrSession(serverID: server.id))
        }
        seerrClient.baseURL = server.url

        // Additionally persist a per-(Jellyfin-user) copy so profile
        // switching can restore the right Seerr session for each
        // profile. Skipped when either ID is missing — callers pass
        // both when they can (SeerrSettingsView has the full app
        // state), nothing when the login happens outside of any
        // Jellyfin-user context.
        if let jellyfinUserID, let jellyfinServerID, let cookie = seerrClient.sessionCookie {
            let remembered = RememberedSeerrSession(
                jellyfinUserID: jellyfinUserID,
                jellyfinServerID: jellyfinServerID,
                seerrServer: server,
                cookie: cookie
            )
            let data = try JSONEncoder().encode(remembered)
            try keychainService.save(
                data,
                for: KeychainKeys.rememberedSeerr(
                    jellyfinServerID: jellyfinServerID,
                    jellyfinUserID: jellyfinUserID
                )
            )
        }
    }

    /// Restore the Seerr session that belongs to a specific Jellyfin
    /// profile. Returns the SeerrServer on success so the caller can
    /// kick off `seerrAuthService.currentUser()` and surface the
    /// result to AppState. Returns nil when the profile has no
    /// remembered Seerr session, in which case the caller should
    /// clear Seerr state.
    func restoreSeerrSession(
        forJellyfinUserID jellyfinUserID: String,
        jellyfinServerID: String
    ) -> SeerrServer? {
        let key = KeychainKeys.rememberedSeerr(
            jellyfinServerID: jellyfinServerID,
            jellyfinUserID: jellyfinUserID
        )
        guard let data = try? keychainService.loadData(for: key),
              let remembered = try? JSONDecoder().decode(RememberedSeerrSession.self, from: data)
        else {
            return nil
        }
        seerrClient.baseURL = remembered.seerrServer.url
        seerrClient.sessionCookie = remembered.cookie
        return remembered.seerrServer
    }

    /// Per-profile Seerr forget — used when a stored Seerr session
    /// fails to restore (server rotated, cookie expired, user
    /// revoked). Leaves other profiles' sessions alone.
    func forgetRememberedSeerr(forJellyfinUserID jellyfinUserID: String, jellyfinServerID: String) {
        try? keychainService.delete(
            for: KeychainKeys.rememberedSeerr(
                jellyfinServerID: jellyfinServerID,
                jellyfinUserID: jellyfinUserID
            )
        )
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
