import Foundation
import Testing
@testable import Sodalite

/// Sodalite#45. Every login path knows exactly one address: LAN discovery pins the internal slot,
/// the address field classifies whatever was typed. A wholesale upsert therefore erased the other
/// slot, and `addServer` marks the record dirty, so the erasure travelled to every other device.
/// tvOS has no URL editor at all (`DualURLEditSheet` is `#if os(iOS)`), so an Apple TV could only
/// ever lose an external URL, never restore one.
@Suite("Server URL slot retention across re-adds", .serialized)
@MainActor
struct ServerURLSlotRetentionTests {
    private let internalURL = URL(string: "http://10.0.0.2:8096")!
    private let externalURL = URL(string: "https://jf.example.com")!

    /// A suite of its own per container. The keychain was the only per-device state these tests had
    /// to separate until the URL slots grew an edit stamp; on `.standard` the container standing in
    /// for the other device reads this one's stamps, and a test earlier in the file that edits the
    /// slots then decides what the later ones see.
    private func makeContainer() -> DependencyContainer {
        DependencyContainer(
            keychainService: InMemoryKeychain(),
            defaults: UserDefaults(suiteName: "slot-retention-\(UUID().uuidString)")!
        )
    }

    private func dualSlotServer(name: String = "Home", version: String? = "10.10.7") -> JellyfinServer {
        JellyfinServer(
            id: "srv1",
            name: name,
            internalURL: internalURL,
            externalURL: externalURL,
            version: version
        )
    }

    private func stored(_ container: DependencyContainer) throws -> JellyfinServer {
        try #require(container.listKnownServers().first(where: { $0.id == "srv1" }))
    }

    /// The reporter's case: iPhone sets the external URL, an Apple TV re-logs in over the LAN.
    @Test func reAddingWithOnlyTheInternalSlotKeepsTheExternalOne() throws {
        let container = makeContainer()
        try container.addServer(dualSlotServer())

        // What ServerDiscoveryViewModel hands back for a LAN hit.
        try container.addServer(JellyfinServer(
            id: "srv1", name: "Home", internalURL: internalURL, externalURL: nil, version: "10.10.7"
        ))

        let server = try stored(container)
        #expect(server.internalURL == internalURL)
        #expect(server.externalURL == externalURL)
    }

    /// Mirror case: signing in through the public hostname must not drop the LAN address.
    @Test func reAddingWithOnlyTheExternalSlotKeepsTheInternalOne() throws {
        let container = makeContainer()
        try container.addServer(dualSlotServer())

        try container.addServer(JellyfinServer(
            id: "srv1", name: "Home", internalURL: nil, externalURL: externalURL, version: "10.10.7"
        ))

        let server = try stored(container)
        #expect(server.internalURL == internalURL)
        #expect(server.externalURL == externalURL)
    }

    /// A re-add still updates the slot it does carry, plus name and version.
    @Test func reAddingUpdatesTheSlotItCarriesAndTheMetadata() throws {
        let container = makeContainer()
        try container.addServer(dualSlotServer(name: "Old name", version: "10.10.6"))

        let movedInternal = URL(string: "http://10.0.0.9:8096")!
        try container.addServer(JellyfinServer(
            id: "srv1", name: "Living Room", internalURL: movedInternal, externalURL: nil, version: "10.10.7"
        ))

        let server = try stored(container)
        #expect(server.internalURL == movedInternal)
        #expect(server.externalURL == externalURL)
        #expect(server.name == "Living Room")
        #expect(server.version == "10.10.7")
    }

    /// Retention must not become a lock: the iOS editor is the one path that may empty a slot.
    @Test func theURLEditorCanStillClearASlot() throws {
        let container = makeContainer()
        try container.addServer(dualSlotServer())

        try container.updateServerURLs(serverID: "srv1", internalURL: internalURL, externalURL: nil)

        let server = try stored(container)
        #expect(server.internalURL == internalURL)
        #expect(server.externalURL == nil)
    }

    /// A synced record is authoritative for both slots, so a deliberate clear on one device still
    /// reaches the others.
    @Test func anIncomingRecordStillClearsASlotItOmits() throws {
        let source = makeContainer()
        try source.addServer(JellyfinServer(
            id: "srv1", name: "Home", internalURL: internalURL, externalURL: nil
        ))
        let payload = try #require(source.collectServerPayload(serverID: "srv1", stamp: Date()))

        let target = makeContainer()
        try target.addServer(dualSlotServer())
        target.applyServerPayload(payload)

        let server = try stored(target)
        #expect(server.externalURL == nil)
    }

    /// The second erasure channel: applying a record left `AppState.activeServer` on the pre-sync
    /// copy, and `switchToUser` persists that copy through `addServer`, so a profile switch wrote
    /// the old slots back and pushed them out again.
    @Test func anIncomingRecordRefreshesTheInMemoryActiveServer() throws {
        let container = makeContainer()
        let appState = AppState()
        container.appState = appState

        let localOnly = JellyfinServer(
            id: "srv1", name: "Home", internalURL: internalURL, externalURL: nil
        )
        try container.addServer(localOnly)
        try container.keychainService.save("srv1", for: KeychainKeys.activeServerID)
        appState.activeServer = localOnly

        let source = makeContainer()
        try source.addServer(dualSlotServer())
        let payload = try #require(source.collectServerPayload(serverID: "srv1", stamp: Date()))
        container.applyServerPayload(payload)

        #expect(appState.activeServer?.externalURL == externalURL)
    }

    // MARK: Seerr

    private let seerrInternal = URL(string: "http://10.0.0.2:5055")!
    private let seerrExternal = URL(string: "https://seerr.example.com")!

    private func containerWithSeerrSession(_ server: SeerrServer) throws -> DependencyContainer {
        let container = makeContainer()
        container.seerrClient.sessionCookie = "connect.sid=abc"
        try container.saveSeerrSession(server: server, forJellyfinUserID: "user-a", jellyfinServerID: "srv1")
        return container
    }

    /// Signing back into Jellyseerr from the LAN must not drop the public address, same as Jellyfin.
    @Test func aSeerrSignInThroughAKnownAddressKeepsTheOtherSlot() throws {
        let container = try containerWithSeerrSession(SeerrServer(
            id: "seerr-1", internalURL: seerrInternal, externalURL: seerrExternal
        ))

        // A fresh discovery mints its own id and classifies the one address it was given.
        let persisted = try container.saveSeerrSession(
            server: SeerrServer(id: "seerr-2", internalURL: seerrInternal, externalURL: nil),
            forJellyfinUserID: "user-a",
            jellyfinServerID: "srv1"
        )

        #expect(persisted.internalURL == seerrInternal)
        #expect(persisted.externalURL == seerrExternal)
    }

    /// A Seerr id is a local UUID, so an unknown address cannot be proven to be the same instance
    /// and must not inherit the previous one's other slot.
    @Test func aSeerrSignInThroughAnUnknownAddressReplacesBothSlots() throws {
        let container = try containerWithSeerrSession(SeerrServer(
            id: "seerr-1", internalURL: seerrInternal, externalURL: seerrExternal
        ))

        let elsewhere = URL(string: "http://10.9.9.9:5055")!
        let persisted = try container.saveSeerrSession(
            server: SeerrServer(id: "seerr-2", internalURL: elsewhere, externalURL: nil),
            forJellyfinUserID: "user-a",
            jellyfinServerID: "srv1"
        )

        #expect(persisted.internalURL == elsewhere)
        #expect(persisted.externalURL == nil)
    }
}
