import Foundation
import Testing
@testable import Sodalite

/// A server record travels as a whole payload with one record-level stamp, and that stamp says when
/// a device last WROTE, not what it last LEARNED. A device that slept through a URL edit therefore
/// republished its stale copy with a fresh stamp and won last-writer-wins against the edit, which is
/// how a corrected external URL came back as the old address on the device that had just fixed it.
///
/// The URL slots carry their own stamp for that reason: only an actual edit moves it, so a
/// republish of unchanged slots cannot outrank one.
@Suite("URL edits outrank a stale republish", .serialized)
@MainActor
struct ServerURLEditPrecedenceTests {
    private let serverID = "srv-url-precedence"
    private let internalURL = URL(string: "http://10.0.0.2:8096")!
    private let oldExternalURL = URL(string: "https://old.example.com")!
    private let newExternalURL = URL(string: "https://new.example.com")!

    private func device() throws -> DependencyContainer {
        // A suite of its own: two containers on `.standard` would share the very URL-edit stamps the
        // merge is meant to be deciding between, which makes them one device wearing two hats.
        let container = DependencyContainer(
            keychainService: InMemoryKeychain(),
            defaults: UserDefaults(suiteName: "url-precedence-\(UUID().uuidString)")!
        )
        try container.addServer(JellyfinServer(
            id: serverID,
            name: "Home",
            internalURL: internalURL,
            externalURL: oldExternalURL
        ))
        return container
    }

    private func payload(_ container: DependencyContainer) throws -> ServerSyncPayload {
        try #require(container.collectServerPayload(serverID: serverID, stamp: Date()))
    }

    private func stored(_ container: DependencyContainer) throws -> JellyfinServer {
        try #require(container.listKnownServers().first(where: { $0.id == serverID }))
    }

    /// The reporter's case: the phone corrects the external URL, the Apple TV slept through it and
    /// republishes what it still holds.
    @Test func aStaleRepublishDoesNotUndoAURLEdit() throws {
        let phone = try device()
        let tv = try device()

        try phone.updateServerURLs(
            serverID: serverID, internalURL: internalURL, externalURL: newExternalURL
        )
        phone.applyServerPayload(try payload(tv))

        #expect(try stored(phone).externalURL == newExternalURL)
    }

    /// The edit still has to travel, or the rule would only have swapped which device loses.
    @Test func aURLEditReachesTheOtherDevice() throws {
        let phone = try device()
        let tv = try device()

        try phone.updateServerURLs(
            serverID: serverID, internalURL: internalURL, externalURL: newExternalURL
        )
        tv.applyServerPayload(try payload(phone))

        #expect(try stored(tv).externalURL == newExternalURL)
    }

    /// Two real edits still order by when they happened, so the later correction wins.
    @Test func theLaterOfTwoEditsWins() throws {
        let phone = try device()
        let tv = try device()

        try tv.updateServerURLs(
            serverID: serverID, internalURL: internalURL, externalURL: oldExternalURL
        )
        try phone.updateServerURLs(
            serverID: serverID, internalURL: internalURL, externalURL: newExternalURL
        )
        tv.applyServerPayload(try payload(phone))

        #expect(try stored(tv).externalURL == newExternalURL)
    }

    /// A device that has never edited the slots must still adopt what it is told, else a fresh
    /// install would keep whatever a login happened to classify into one slot.
    @Test func aDeviceThatNeverEditedAdoptsTheIncomingSlots() throws {
        let phone = try device()
        let fresh = try device()

        try phone.updateServerURLs(
            serverID: serverID, internalURL: internalURL, externalURL: newExternalURL
        )
        fresh.applyServerPayload(try payload(phone))

        #expect(try stored(fresh).externalURL == newExternalURL)
    }
}
