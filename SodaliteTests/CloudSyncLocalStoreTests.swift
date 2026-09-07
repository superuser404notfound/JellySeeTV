import Foundation
import Testing
@testable import Sodalite

/// In-memory KeychainServiceProtocol so the container round-trips without SecItem.
nonisolated final class InMemoryKeychain: KeychainServiceProtocol, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func save(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
    func save(_ string: String, for key: String) throws {
        try save(Data(string.utf8), for: key)
    }
    func loadData(for key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
    func loadString(for key: String) throws -> String? {
        try loadData(for: key).flatMap { String(data: $0, encoding: .utf8) }
    }
    func delete(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
    func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}

@Suite("CloudSync local collect/apply", .serialized)
@MainActor
struct CloudSyncLocalStoreTests {
    private static let accentChoiceKey = "appearance.accentChoice"
    private static let backgroundStyleKey = "appearance.backgroundStyle"

    private func makeContainer() -> DependencyContainer {
        DependencyContainer(keychainService: InMemoryKeychain())
    }

    private func withStoredAppearanceIDs(
        accent: String,
        background: String,
        perform: (DependencyContainer, UserDefaults) -> Void
    ) {
        let defaults = UserDefaults.standard
        let previousAccent = defaults.object(forKey: Self.accentChoiceKey)
        let previousBackground = defaults.object(forKey: Self.backgroundStyleKey)
        defer {
            if let previousAccent {
                defaults.set(previousAccent, forKey: Self.accentChoiceKey)
            } else {
                defaults.removeObject(forKey: Self.accentChoiceKey)
            }
            if let previousBackground {
                defaults.set(previousBackground, forKey: Self.backgroundStyleKey)
            } else {
                defaults.removeObject(forKey: Self.backgroundStyleKey)
            }
        }

        defaults.set(accent, forKey: Self.accentChoiceKey)
        defaults.set(background, forKey: Self.backgroundStyleKey)
        perform(makeContainer(), defaults)
    }

    private var sampleServer: JellyfinServer {
        JellyfinServer(id: "srv1", name: "Main", url: URL(string: "https://jf.example")!, version: "10.10")
    }

    @Test("server payload round-trips through keychain")
    func serverRoundTrip() throws {
        let source = makeContainer()
        try source.addServer(sampleServer)
        try source.rememberUser(RememberedUser(id: "u1", serverID: "srv1", name: "vincent", imageTag: nil, token: "tok1"))

        let payload = source.collectServerPayload(serverID: "srv1", stamp: Date(timeIntervalSince1970: 7))
        let unwrapped = try #require(payload)
        #expect(unwrapped.server == sampleServer)
        #expect(unwrapped.rememberedUsers.map(\.id) == ["u1"])
        #expect(unwrapped.updatedAt == Date(timeIntervalSince1970: 7))

        let target = makeContainer()
        target.applyServerPayload(unwrapped)
        #expect(target.listKnownServers() == [sampleServer])
        #expect(target.listRememberedUsers(serverID: "srv1").map(\.id) == ["u1"])
    }

    @Test("collect returns nil for an unknown server")
    func collectUnknown() {
        #expect(makeContainer().collectServerPayload(serverID: "nope", stamp: Date()) == nil)
    }

    @Test("apply upserts without reordering existing servers")
    func applyKeepsOrder() throws {
        let container = makeContainer()
        try container.addServer(sampleServer)
        let second = JellyfinServer(id: "srv2", name: "Second", url: URL(string: "https://two.example")!, version: nil)
        let payload = ServerSyncPayload(updatedAt: Date(), server: second, rememberedUsers: [],
                                        jellyfinPassword: nil, passwordUserID: nil, seerrSessions: [], homeRows: nil)
        container.applyServerPayload(payload)
        // Remote-added server appends; it must not hijack the local MRU front slot.
        #expect(container.listKnownServers().map(\.id) == ["srv1", "srv2"])
    }

    @Test("remote server deletion removes all scoped state")
    func remoteDeletion() throws {
        let container = makeContainer()
        try container.addServer(sampleServer)
        try container.rememberUser(RememberedUser(id: "u1", serverID: "srv1", name: "v", imageTag: nil, token: "t"))
        container.applyRemoteServerDeletion(serverID: "srv1")
        #expect(container.listKnownServers().isEmpty)
        #expect(container.listRememberedUsers(serverID: "srv1").isEmpty)
    }

    @Test("collect carries one password per profile, plus the legacy pair for older builds")
    func passwordsPerProfile() throws {
        let container = makeContainer()
        try container.addServer(sampleServer)
        try container.keychainService.save(
            "pw", for: KeychainKeys.jellyfinPassword(serverID: "srv1", userID: "u1")
        )
        try container.keychainService.save("u1", for: KeychainKeys.userID(serverID: "srv1"))
        let payload = try #require(container.collectServerPayload(serverID: "srv1", stamp: Date()))
        #expect(payload.jellyfinPasswords == ["u1": "pw"])
        #expect(payload.jellyfinPassword == "pw")
        #expect(payload.passwordUserID == "u1")
    }

    /// A device that signed in with Quick Connect or the picker has no password to send. Reading
    /// that as "there is none" once let it strip the password from every other device.
    @Test("apply keeps a local password when the payload carries none")
    func applyKeepsLocalPassword() throws {
        let container = makeContainer()
        try container.addServer(sampleServer)
        try container.keychainService.save(
            "pw", for: KeychainKeys.jellyfinPassword(serverID: "srv1", userID: "u1")
        )
        try container.keychainService.save("u1", for: KeychainKeys.userID(serverID: "srv1"))

        let payload = ServerSyncPayload(updatedAt: Date(), server: sampleServer, rememberedUsers: [],
                                        jellyfinPassword: nil, passwordUserID: nil, seerrSessions: [], homeRows: nil)
        container.applyServerPayload(payload)

        #expect(try container.keychainService.loadString(
            for: KeychainKeys.jellyfinPassword(serverID: "srv1", userID: "u1")
        ) == "pw")
    }

    /// A payload from a build that predates the per-user layout still lands on the right profile.
    @Test("apply accepts the legacy single-password fields")
    func applyAcceptsLegacyPasswordFields() throws {
        let container = makeContainer()
        try container.addServer(sampleServer)
        try container.keychainService.save("u1", for: KeychainKeys.userID(serverID: "srv1"))

        let payload = ServerSyncPayload(updatedAt: Date(), server: sampleServer, rememberedUsers: [],
                                        jellyfinPassword: "pw", passwordUserID: "u1",
                                        seerrSessions: [], homeRows: nil)
        container.applyServerPayload(payload)

        #expect(try container.keychainService.loadString(
            for: KeychainKeys.jellyfinPassword(serverID: "srv1", userID: "u1")
        ) == "pw")
    }

    /// Sodalite#45: a profile missing from the payload is no longer a removal (the sender may just be
    /// behind), so the session goes with the published removal instead.
    @Test("apply forgets seerr sessions of users the payload reports as removed")
    func applyForgetsRemovedUsersSessions() throws {
        let container = makeContainer()
        try container.addServer(sampleServer)
        try container.rememberUser(RememberedUser(id: "u2", serverID: "srv1", name: "old", imageTag: nil, token: "t2"))
        let session = RememberedSeerrSession(jellyfinUserID: "u2", jellyfinServerID: "srv1",
                                             seerrServer: SeerrServer(id: "se", url: URL(string: "https://se.example")!), cookie: "c")
        try container.keychainService.save(try JSONEncoder().encode(session),
                                           for: KeychainKeys.rememberedSeerr(jellyfinServerID: "srv1", jellyfinUserID: "u2"))
        let payload = ServerSyncPayload(updatedAt: Date(), server: sampleServer, rememberedUsers: [],
                                        jellyfinPassword: nil, passwordUserID: nil, seerrSessions: [], homeRows: nil,
                                        forgottenUsers: ["u2": Date()])
        container.applyServerPayload(payload)
        #expect(try container.keychainService.loadData(for: KeychainKeys.rememberedSeerr(jellyfinServerID: "srv1", jellyfinUserID: "u2")) == nil)
        #expect(container.listRememberedUsers(serverID: "srv1").isEmpty)
    }

    @Test("settings payloads round-trip through the stores")
    func settingsRoundTrip() {
        let source = makeContainer()
        source.appearancePreferences.accentChoice = .ocean
        source.appearancePreferences.backgroundStyle = .accentAurora
        source.appearancePreferences.largeCards = true
        let payload = source.collectSettingsPayload(.appearance, stamp: Date(timeIntervalSince1970: 3))
        guard case .appearance(let inner) = payload else { Issue.record("wrong case"); return }
        #expect(inner.accentChoice == "ocean")
        #expect(inner.backgroundStyle == BackgroundStyle.accentAurora.rawValue)
        #expect(inner.largeCards == true)

        let target = makeContainer()
        target.applySettingsPayload(payload)
        #expect(target.appearancePreferences.accentChoice == .ocean)
        #expect(target.appearancePreferences.backgroundStyle == .accentAurora)
        #expect(target.appearancePreferences.largeCards == true)
    }

    @Test("unknown enum raw value keeps the current store value")
    func enumFallback() {
        let container = makeContainer()
        container.appearancePreferences.accentChoice = .gold
        container.appearancePreferences.backgroundStyle = .oledBlack
        let payload = SettingsSyncPayload.appearance(AppearanceSettingsPayload(
            updatedAt: Date(), accentChoice: "fromTheFuture", backgroundStyle: "fromTheFuture",
            showContentLogos: true,
            continueWatchingImage: "still", largeCards: false, nowPlayingUsesSeriesPoster: false))
        container.applySettingsPayload(payload)
        #expect(container.appearancePreferences.accentChoice == .gold)
        #expect(container.appearancePreferences.backgroundStyle == .oledBlack)
    }

    @Test("unknown stored appearance IDs render fallbacks and collect losslessly")
    func unknownStoredAppearanceIDs() {
        withStoredAppearanceIDs(
            accent: "futureAccent",
            background: "futureBackground"
        ) { container, defaults in
            let appearance = container.appearancePreferences
            #expect(appearance.accentChoice == .systemBlue)
            #expect(appearance.backgroundStyle == .graphiteGlass)
            #expect(appearance.resolvedTheme(isSupporter: true) == .default)

            appearance.largeCards.toggle()
            let payload = container.collectSettingsPayload(
                .appearance,
                stamp: Date(timeIntervalSince1970: 4)
            )
            guard case .appearance(let collected) = payload else {
                Issue.record("wrong case")
                return
            }
            #expect(collected.accentChoice == "futureAccent")
            #expect(collected.backgroundStyle == "futureBackground")

            appearance.accentChoice = .orange
            appearance.backgroundStyle = .oledBlack
            #expect(defaults.string(forKey: Self.accentChoiceKey) == "orange")
            #expect(defaults.string(forKey: Self.backgroundStyleKey) == "oledBlack")
            let selectedPayload = container.collectSettingsPayload(
                .appearance,
                stamp: Date(timeIntervalSince1970: 5)
            )
            guard case .appearance(let selected) = selectedPayload else {
                Issue.record("wrong case")
                return
            }
            #expect(selected.accentChoice == "orange")
            #expect(selected.backgroundStyle == "oledBlack")
        }
    }

    @Test("unknown remote appearance IDs preserve unknown local stored IDs")
    func unknownRemoteAppearanceIDs() {
        withStoredAppearanceIDs(
            accent: "futureAccent",
            background: "futureBackground"
        ) { container, defaults in
            let unknown = SettingsSyncPayload.appearance(AppearanceSettingsPayload(
                updatedAt: Date(timeIntervalSince1970: 5),
                accentChoice: "newerFutureAccent",
                backgroundStyle: "newerFutureBackground",
                showContentLogos: false,
                continueWatchingImage: "backdrop",
                largeCards: true,
                nowPlayingUsesSeriesPoster: true
            ))

            container.applySettingsPayload(unknown)

            #expect(defaults.string(forKey: Self.accentChoiceKey) == "futureAccent")
            #expect(defaults.string(forKey: Self.backgroundStyleKey) == "futureBackground")
            #expect(container.appearancePreferences.showContentLogos == false)
            #expect(container.appearancePreferences.continueWatchingImage == .backdrop)
            #expect(container.appearancePreferences.largeCards == true)
            #expect(container.appearancePreferences.nowPlayingUsesSeriesPoster == true)
            let payload = container.collectSettingsPayload(
                .appearance,
                stamp: Date(timeIntervalSince1970: 6)
            )
            guard case .appearance(let collected) = payload else {
                Issue.record("wrong case")
                return
            }
            #expect(collected.accentChoice == "futureAccent")
            #expect(collected.backgroundStyle == "futureBackground")
        }
    }

    @Test("security payload round-trips the PIN blob")
    func securityRoundTrip() throws {
        let source = makeContainer()
        try source.saveGuardianPIN("2468")
        let payload = try #require(source.collectSecurityPayload(stamp: Date(timeIntervalSince1970: 9)))

        let target = makeContainer()
        target.applySecurityPayload(payload)
        #expect(target.isGuardianPINSet())
        #expect(target.verifyGuardianPIN("2468") == .success)
        target.applyRemoteSecurityDeletion()
        #expect(!target.isGuardianPINSet())
    }

    private func makePreferences() -> CloudSyncPreferences {
        CloudSyncPreferences(store: UserDefaults(suiteName: "CloudSyncLocalStoreTests-\(UUID().uuidString)")!)
    }

    @Test("waitForInitialSync returns immediately once adoption has completed")
    func waitForInitialSyncAdoptionCompleted() async {
        let prefs = makePreferences()
        prefs.adoptionCompleted = true
        let service = CloudSyncService(dependencies: makeContainer(), preferences: prefs)
        let start = Date()
        await service.waitForInitialSync(timeout: 5)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test("waitForInitialSync returns immediately for a never-started, disabled service")
    func waitForInitialSyncDisabledStatus() async {
        let prefs = makePreferences()
        prefs.isEnabled = false
        // Never call start(): status stays at its .disabled default without touching CloudKit.
        let service = CloudSyncService(dependencies: makeContainer(), preferences: prefs)
        let start = Date()
        await service.waitForInitialSync(timeout: 5)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test("waitForInitialSync polls until the timeout when neither adoption nor a terminal status holds")
    func waitForInitialSyncTimesOut() async {
        let prefs = makePreferences()
        let service = CloudSyncService(dependencies: makeContainer(), preferences: prefs)
        service.setStatusForTesting(.active(lastSyncAt: nil))
        let start = Date()
        await service.waitForInitialSync(timeout: 0.5)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.4)
        #expect(elapsed < 3)
    }
}
