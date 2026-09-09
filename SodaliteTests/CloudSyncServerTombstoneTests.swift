import Foundation
import Testing
@testable import Sodalite

/// Removing a server had no way to travel as a removal. The record was deleted in CloudKit and the
/// local LWW stamp thrown away with it, so the moment any other device republished that server (a
/// re-login, a default-server pin, a version refresh all mark it dirty) the record came back, and
/// the device that had just deleted it read its own missing stamp as `.distantPast` and adopted the
/// resurrection unconditionally. From the outside: the server cannot be removed except by wiping
/// the app.
///
/// Profiles already solved this (`forgottenUsers`, Sodalite#45): a removal is published as such and
/// only a deliberate re-add takes it back. Servers now carry the same tombstone.
@Suite("Removed servers travel as removals", .serialized)
@MainActor
struct CloudSyncServerTombstoneTests {
    private let serverID = "srv-tombstone"
    private let otherID = "srv-tombstone-other"
    private let internalURL = URL(string: "http://10.0.0.2:8096")!

    private func server(_ id: String) -> JellyfinServer {
        JellyfinServer(id: id, name: "Home \(id)", internalURL: internalURL, externalURL: nil)
    }

    private func device(_ ids: [String]) throws -> DependencyContainer {
        // A suite of its own, so each container carries its own tombstone map and added-at stamps.
        let container = DependencyContainer(
            keychainService: InMemoryKeychain(),
            defaults: UserDefaults(suiteName: "server-tombstone-\(UUID().uuidString)")!
        )
        for id in ids { try container.addServer(server(id)) }
        return container
    }

    private func payload(_ container: DependencyContainer, _ id: String) throws -> ServerSyncPayload {
        try #require(container.collectServerPayload(serverID: id, stamp: Date()))
    }

    private func serverIDs(_ container: DependencyContainer) -> [String] {
        container.listKnownServers().map(\.id).sorted()
    }

    /// The reporter's case: the record comes back from a device that has not heard about the removal.
    @Test func aStaleRecordDoesNotResurrectARemovedServer() throws {
        let phone = try device([serverID])
        let tv = try device([serverID])
        let stale = try payload(tv, serverID)

        try phone.removeServer(id: serverID)
        phone.applyServerPayload(stale)

        #expect(serverIDs(phone).isEmpty)
    }

    /// The removal reaches the other device through the auth record it rides on.
    @Test func aRemovalTravelsToTheOtherDevice() throws {
        let phone = try device([serverID])
        let tv = try device([serverID])

        try phone.removeServer(id: serverID)
        tv.applySettingsPayload(phone.collectSettingsPayload(.auth, stamp: Date()))

        #expect(serverIDs(tv).isEmpty)
    }

    /// A removal must not take the servers standing beside it.
    @Test func aRemovalOnlyTakesItsOwnServer() throws {
        let phone = try device([serverID, otherID])
        let tv = try device([serverID, otherID])

        try phone.removeServer(id: serverID)
        tv.applySettingsPayload(phone.collectSettingsPayload(.auth, stamp: Date()))

        #expect(serverIDs(tv) == [otherID])
    }

    /// The map is a union, so it must survive the record losing last-writer-wins. This is the shape
    /// `CloudSyncService` reaches for directly when the auth record it fetched is older than what
    /// this device last wrote: without it, a device that changed some unrelated auth setting more
    /// recently discards the whole payload and the removed server stands there for good.
    @Test func removalsApplyEvenWhenTheRecordLosesLastWriterWins() throws {
        let phone = try device([serverID])
        let tv = try device([serverID])

        try phone.removeServer(id: serverID)
        tv.applyForgottenServers(phone.authPreferences.forgottenServers)

        #expect(serverIDs(tv).isEmpty)
    }

    /// Signing back in is the deliberate act that takes the removal back, the same rule profiles use.
    /// Without it the two devices would hand the server back and forth forever.
    @Test func aReAddSurvivesTheOtherDevicesTombstone() throws {
        // Both devices hold the server BEFORE the removal, which is the case the rule is about: a
        // device that added it afterwards has already said something newer than the removal.
        let removing = try device([serverID])
        let readding = try device([serverID])
        try removing.removeServer(id: serverID)

        readding.applySettingsPayload(removing.collectSettingsPayload(.auth, stamp: Date()))
        #expect(serverIDs(readding).isEmpty)

        try readding.addServer(server(serverID))
        removing.applyServerPayload(try payload(readding, serverID))

        #expect(serverIDs(removing) == [serverID])
    }
}
