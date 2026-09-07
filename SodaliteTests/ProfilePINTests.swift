import Foundation
import Testing
@testable import Sodalite

@MainActor
struct ProfilePINTests {

    @Test("A ProfileRef composes the same id the store has always used")
    func refMatchesLegacyComposite() {
        let ref = ProfileRef(serverID: "A", userID: "dad")
        #expect(ref.compositeID == ParentalControlsPreferences.compositeID(serverID: "A", userID: "dad"))
        #expect(ref.id == ref.compositeID)
    }

    @Test("The ref-first store API and the legacy forwarders agree")
    func refAPIMatchesForwarders() {
        let prefs = ParentalControlsPreferences(store: UserDefaults(suiteName: "ProfilePINTests.refAPI")!)
        let ref = ProfileRef(serverID: "A", userID: "mum")
        prefs.setRole(.pinToEnter, for: ref)
        #expect(prefs.role(ref) == .pinToEnter)
        #expect(prefs.role(serverID: "A", userID: "mum") == .pinToEnter)
        prefs.setRole(.pinToLeave, serverID: "A", userID: "mum")
        #expect(prefs.role(ref) == .pinToLeave)
        #expect(prefs.isProtected(ref))
    }

    // MARK: Storage and doors

    /// Every container gets its own `InMemoryKeychain`, the way the other parental suites build
    /// theirs, so no PIN blob ever touches the device keychain and no cleanup is owed.
    ///
    /// The profiles have to be REGISTERED, not just named: `profilesWithOwnPIN()` enumerates known
    /// servers times remembered users, so a PIN saved for a profile the container has never heard of
    /// is invisible to the collision check and to the sync sweep.
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

    @Test("A profile door takes its own PIN and the Guardian PIN, another profile's opens nothing")
    func doorAcceptsOwnAndGuardian() throws {
        let container = try makeHousehold(["family", "dad"])
        let family = ProfileRef(serverID: "A", userID: "family")
        let dad = ProfileRef(serverID: "A", userID: "dad")

        try container.saveGuardianPIN("9999")
        try container.saveOwnPIN("1111", for: family)
        try container.saveOwnPIN("2222", for: dad)

        #expect(container.verifyPIN("1111", for: .profile(family)) == .success)
        #expect(container.verifyPIN("9999", for: .profile(family)) == .success)
        if case .success = container.verifyPIN("2222", for: .profile(family)) {
            Issue.record("another profile's own PIN opened this door")
        }
        if case .success = container.verifyPIN("1111", for: .guardian) {
            Issue.record("an own PIN opened the Guardian door")
        }
    }

    @Test("A locked profile door leaves the Guardian door open")
    func throttleIsPerDoor() throws {
        let container = try makeHousehold(["family", "dad"])
        let family = ProfileRef(serverID: "A", userID: "family")

        try container.saveGuardianPIN("9999")
        try container.saveOwnPIN("1111", for: family)

        for _ in 0..<5 { _ = container.verifyPIN("0000", for: .profile(family)) }

        #expect(container.pinLockout(for: .profile(family)) != nil)
        #expect(container.pinLockout(for: .guardian) == nil)
        #expect(container.verifyPIN("9999", for: .guardian) == .success)
    }

    @Test("The Guardian PIN used at a profile door clears both counters")
    func guardianSuccessClearsBothThrottles() throws {
        let container = try makeHousehold(["family", "dad"])
        let family = ProfileRef(serverID: "A", userID: "family")

        try container.saveGuardianPIN("9999")
        try container.saveOwnPIN("1111", for: family)

        _ = container.verifyPIN("0000", for: .guardian)
        _ = container.verifyPIN("0000", for: .profile(family))
        #expect(container.verifyPIN("9999", for: .profile(family)) == .success)

        // Four more misses at the Guardian door would lock it out if its counter had survived.
        for _ in 0..<4 { _ = container.verifyPIN("0000", for: .guardian) }
        #expect(container.pinLockout(for: .guardian) == nil)
    }

    @Test("A PIN that already opens another door is refused")
    func collisionIsRefused() throws {
        let container = try makeHousehold(["family", "dad"])
        let family = ProfileRef(serverID: "A", userID: "family")
        let dad = ProfileRef(serverID: "A", userID: "dad")

        try container.saveGuardianPIN("9999")
        try container.saveOwnPIN("1111", for: family)

        #expect(container.pinCollides("9999", excluding: dad))
        #expect(container.pinCollides("1111", excluding: dad))
        #expect(!container.pinCollides("1111", excluding: family))
        #expect(!container.pinCollides("3333", excluding: dad))
        // A new Guardian PIN must not repeat a profile's own PIN either.
        #expect(container.pinCollides("1111", excluding: nil))
    }

    // MARK: Cleanup

    @Test("A role that is not pinToEnter has no door, so its PIN goes with it")
    func roleChangeClearsTheOwnPIN() throws {
        let container = try makeHousehold(["family", "dad"])
        let family = ProfileRef(serverID: "A", userID: "family")
        // Roles live in the shared UserDefaults suite, so this one does need putting back.
        defer { container.parentalControlsPreferences.setRole(.open, for: family) }

        try container.saveGuardianPIN("9999")
        container.setLockRole(.pinToEnter, for: family)
        try container.saveOwnPIN("1111", for: family)
        #expect(container.hasOwnPIN(family))

        container.setLockRole(.open, for: family)
        #expect(!container.hasOwnPIN(family))
        #expect(container.parentalControlsPreferences.role(family) == .open)
    }

    @Test("Turning parental controls off takes every own PIN with it")
    func clearingTheGuardianPINClearsThemAll() throws {
        let container = try makeHousehold(["family", "dad"])
        let family = ProfileRef(serverID: "A", userID: "family")

        try container.saveGuardianPIN("9999")
        try container.saveOwnPIN("1111", for: family)

        try container.clearGuardianPIN()
        #expect(!container.hasOwnPIN(family))
        #expect(!container.isGuardianPINSet())
    }

    @Test("Forgetting a profile takes its PIN, so a returning profile does not inherit it")
    func purgeTakesTheOwnPIN() throws {
        let container = try makeHousehold(["family", "dad"])
        let family = ProfileRef(serverID: "A", userID: "family")

        try container.saveGuardianPIN("9999")
        try container.saveOwnPIN("1111", for: family)

        container.purgeUserCredentials(id: family.userID, serverID: family.serverID)
        #expect(!container.hasOwnPIN(family))
    }
}
