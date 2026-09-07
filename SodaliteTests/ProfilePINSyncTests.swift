import Foundation
import Testing
@testable import Sodalite

@MainActor
struct ProfilePINSyncTests {

    /// The security record exactly as it was written before own PINs existed. Encoded with the same
    /// bare `JSONEncoder` CloudSyncService uses, so the test cannot pass by guessing a date or data
    /// strategy the real path does not set.
    private struct LegacySecurityPayload: Codable {
        var schemaVersion: Int = 1
        var updatedAt: Date
        var pinBlob: GuardianPINCrypto.Blob
    }

    private func makeHousehold(_ userIDs: [String]) throws -> DependencyContainer {
        let container = DependencyContainer(keychainService: InMemoryKeychain())
        try container.addServer(JellyfinServer(id: "A", name: "Main",
                                               url: URL(string: "https://jf.example")!,
                                               version: "10.10"))
        for id in userIDs {
            try container.rememberUser(RememberedUser(id: id, serverID: "A", name: id,
                                                      imageTag: nil, token: "t-\(id)"))
        }
        return container
    }

    @Test("A record written before own PINs existed still decodes")
    func oldRecordDecodes() throws {
        let blob = GuardianPINCrypto.makeBlob(pin: "9999")
        let legacy = LegacySecurityPayload(updatedAt: Date(timeIntervalSince1970: 760_000_000),
                                           pinBlob: blob)
        let data = try JSONEncoder().encode(legacy)

        let payload = try JSONDecoder().decode(SecuritySyncPayload.self, from: data)
        #expect(payload.profilePINs.isEmpty)
        #expect(payload.pinBlob == blob)
        #expect(payload.schemaVersion == 1)
    }

    @Test("A payload round trips its own PINs")
    func roundTrip() throws {
        let payload = SecuritySyncPayload(
            updatedAt: Date(timeIntervalSince1970: 760_000_000),
            pinBlob: GuardianPINCrypto.makeBlob(pin: "9999"),
            profilePINs: [
                .init(serverID: "A", userID: "family", blob: GuardianPINCrypto.makeBlob(pin: "1111"))
            ]
        )
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(SecuritySyncPayload.self, from: data) == payload)
    }

    @Test("Applying a record writes what it names and drops what it does not")
    func applyIsAuthoritative() throws {
        // Both profiles are registered, else the deletion sweep enumerates nothing and this would
        // pass without exercising it.
        let container = try makeHousehold(["family", "dad"])
        let family = ProfileRef(serverID: "A", userID: "family")
        let dad = ProfileRef(serverID: "A", userID: "dad")

        try container.saveGuardianPIN("9999")
        try container.saveOwnPIN("2222", for: dad)

        let arriving = SecuritySyncPayload(
            updatedAt: Date(),
            pinBlob: GuardianPINCrypto.makeBlob(pin: "8888"),
            profilePINs: [
                .init(serverID: family.serverID, userID: family.userID,
                      blob: GuardianPINCrypto.makeBlob(pin: "1111"))
            ]
        )
        container.applySecurityPayload(arriving)

        #expect(container.verifyPIN("1111", for: .profile(family)) == .success)
        #expect(container.verifyPIN("8888", for: .guardian) == .success)
        // The record is authoritative for the whole list, so a profile it does not name loses its
        // PIN and falls back to the Guardian door.
        #expect(!container.hasOwnPIN(dad))
    }

    @Test("Collecting a payload lists every own PIN the device holds, in a stable order")
    func collectListsThemSorted() throws {
        let container = try makeHousehold(["dad", "family"])
        try container.saveGuardianPIN("9999")
        try container.saveOwnPIN("1111", for: ProfileRef(serverID: "A", userID: "family"))
        try container.saveOwnPIN("2222", for: ProfileRef(serverID: "A", userID: "dad"))

        let payload = try #require(container.collectSecurityPayload(stamp: Date()))
        #expect(payload.profilePINs.map(\.userID) == ["dad", "family"])
    }
}
