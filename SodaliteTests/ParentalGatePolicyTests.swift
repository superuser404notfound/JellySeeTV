import Testing
import Foundation
@testable import Sodalite

/// The full matrix. A lock is a property of the door: the role of the target decides, and the role
/// of the active profile only ever adds the leave-lock. There is no cold-start term, see
/// `ParentalGatePolicy` for why the one that existed before #105 became the migration instead.
struct ParentalGatePolicyTests {

    // MARK: entering a leave-locked (today's "protected") profile is always free

    @Test func enteringALeaveLockedProfileIsFreeFromAnywhere() {
        for active in ProfileLockRole.allCases {
            #expect(ParentalGatePolicy.gateRequiredForActivating(
                targetRole: .pinToLeave, activeRole: active) == false)
        }
    }

    // MARK: an entry-locked profile always costs the PIN

    @Test func enteringAnEntryLockedProfileAlwaysCostsThePIN() {
        for active in ProfileLockRole.allCases {
            #expect(ParentalGatePolicy.gateRequiredForActivating(
                targetRole: .pinToEnter, activeRole: active))
        }
    }

    // MARK: an open profile is open, except as the far side of a leave-lock

    @Test func anOpenProfileIsFreeToEnter() {
        #expect(ParentalGatePolicy.gateRequiredForActivating(
            targetRole: .open, activeRole: .open) == false)
        #expect(ParentalGatePolicy.gateRequiredForActivating(
            targetRole: .open, activeRole: .pinToEnter) == false)
    }

    /// This branch is what enforces pinToLeave: without it, the child walks out of their locked-in
    /// profile into any open one.
    @Test func leavingALockedInProfileForAnOpenOneCostsThePIN() {
        #expect(ParentalGatePolicy.gateRequiredForActivating(
            targetRole: .open, activeRole: .pinToLeave))
    }

    /// The reprompt's "continue as current" taps the ACTIVE card, so target and active are the same
    /// profile. Only the entry-locked reading may cost the PIN there.
    @Test func continuingAsTheCurrentProfileIsGatedOnlyWhenItIsEntryLocked() {
        #expect(ParentalGatePolicy.gateRequiredForActivating(
            targetRole: .pinToEnter, activeRole: .pinToEnter))
        #expect(ParentalGatePolicy.gateRequiredForActivating(
            targetRole: .open, activeRole: .open) == false)
        #expect(ParentalGatePolicy.gateRequiredForActivating(
            targetRole: .pinToLeave, activeRole: .pinToLeave) == false)
    }

    // MARK: session-scoped escapes

    /// Only a profile that cannot be opened without the PIN carries a trusted occupant. The open
    /// case is the one this pins hardest: it is where a child sits in the household the discussion
    /// described, and leaving it ungated handed them server management, tabs and the logout.
    @Test func onlyAnEntryLockedProfileIsTrustedWithTheEscapes() {
        #expect(ParentalGatePolicy.sessionActionRequiresPIN(activeRole: .pinToEnter,
                                                           activeHasOwnPIN: false) == false)
        #expect(ParentalGatePolicy.sessionActionRequiresPIN(activeRole: .open,
                                                           activeHasOwnPIN: false))
        #expect(ParentalGatePolicy.sessionActionRequiresPIN(activeRole: .pinToLeave,
                                                           activeHasOwnPIN: false))
    }

    // MARK: prompt copy

    @Test func entryLockedTargetGetsItsOwnPrompt() {
        let ref = ProfileRef(serverID: "A", userID: "dad")
        #expect(ParentalGatePolicy.reason(forActivating: .pinToEnter, ref: ref) == .enterProfile(ref))
    }

    @Test func everyOtherTargetKeepsTheSwitchPrompt() {
        let ref = ProfileRef(serverID: "A", userID: "dad")
        #expect(ParentalGatePolicy.reason(forActivating: .open, ref: ref) == .switchProfile)
        #expect(ParentalGatePolicy.reason(forActivating: .pinToLeave, ref: ref) == .switchProfile)
    }
}

/// `parentalControlsActive()` is a conjunction of a keychain read and a store read, and only the
/// container sees both halves. The store behind it is `UserDefaults.standard`, shared with every
/// other suite, so each test puts it back the way it found it.
@MainActor
struct ParentalControlsActiveTests {
    /// Gap 1 from the spec: an entry lock alone arms parental controls, with nobody locked in.
    @Test func entryLockAloneArmsParentalControls() throws {
        let container = DependencyContainer(keychainService: InMemoryKeychain())
        try container.saveGuardianPIN("1234")
        container.parentalControlsPreferences.setRole(.pinToEnter, serverID: "A", userID: "dad")
        defer { container.parentalControlsPreferences.setRole(.open, serverID: "A", userID: "dad") }
        #expect(container.parentalControlsPreferences.protectedProfileIDs.isEmpty)
        #expect(container.parentalControlsActive())
    }

    @Test func aPinWithNoLockedProfileIsNotActive() throws {
        let container = DependencyContainer(keychainService: InMemoryKeychain())
        try container.saveGuardianPIN("1234")
        let previousProtected = container.parentalControlsPreferences.protectedProfileIDs
        let previousEntry = container.parentalControlsPreferences.entryLockedProfileIDs
        container.parentalControlsPreferences.protectedProfileIDs = []
        container.parentalControlsPreferences.entryLockedProfileIDs = []
        defer {
            container.parentalControlsPreferences.protectedProfileIDs = previousProtected
            container.parentalControlsPreferences.entryLockedProfileIDs = previousEntry
        }
        #expect(container.parentalControlsActive() == false)
    }

    @Test func locksWithoutAPinAreNotActive() {
        let container = DependencyContainer(keychainService: InMemoryKeychain())
        container.parentalControlsPreferences.setRole(.pinToEnter, serverID: "A", userID: "dad")
        defer { container.parentalControlsPreferences.setRole(.open, serverID: "A", userID: "dad") }
        #expect(container.parentalControlsActive() == false)
    }
}

/// Before #105 an unmarked profile still cost the PIN at a cold start, and "unmarked" is what the
/// new model calls open, which costs nothing. Upgrading without this would unlock every adult
/// profile on the device in place.
@Suite(.serialized)
@MainActor
struct ParentalEntryLockMigrationTests {
    private let latch = "parental.entryLockMigrationDone"

    private func device() throws -> DependencyContainer {
        let container = DependencyContainer(keychainService: InMemoryKeychain())
        let server = JellyfinServer(id: "A", name: "A", url: URL(string: "https://a.example.com")!)
        try container.addServer(server)
        for id in ["kid", "mum", "dad"] {
            try container.rememberUser(
                RememberedUser(id: id, serverID: "A", name: id, imageTag: nil, token: "tok-\(id)")
            )
        }
        return container
    }

    private func clean(_ container: DependencyContainer) {
        UserDefaults.standard.removeObject(forKey: latch)
        for id in ["kid", "mum", "dad"] {
            container.parentalControlsPreferences.setRole(.open, serverID: "A", userID: id)
        }
    }

    @Test func anInstallWithALockReadsItsUnmarkedProfilesAsEntryLocked() throws {
        let container = try device()
        defer { clean(container) }
        UserDefaults.standard.removeObject(forKey: latch)
        try container.saveGuardianPIN("1234")
        container.parentalControlsPreferences.setRole(.pinToLeave, serverID: "A", userID: "kid")

        container.migrateUnmarkedProfilesToEntryLocked()

        #expect(container.parentalControlsPreferences.role(serverID: "A", userID: "kid") == .pinToLeave)
        #expect(container.parentalControlsPreferences.role(serverID: "A", userID: "mum") == .pinToEnter)
        #expect(container.parentalControlsPreferences.role(serverID: "A", userID: "dad") == .pinToEnter)
    }

    /// No PIN, or no locked profile: there was no lock to preserve, and marking every profile would
    /// invent one the user never asked for.
    @Test func anInstallWithoutALockIsLeftAlone() throws {
        let container = try device()
        defer { clean(container) }
        UserDefaults.standard.removeObject(forKey: latch)
        try container.saveGuardianPIN("1234")

        container.migrateUnmarkedProfilesToEntryLocked()

        #expect(container.parentalControlsPreferences.entryLockedProfileIDs.isEmpty)
    }

    /// Latched, so a profile deliberately set back to open later does not get re-locked on the next
    /// launch.
    @Test func itRunsOnce() throws {
        let container = try device()
        defer { clean(container) }
        UserDefaults.standard.removeObject(forKey: latch)
        try container.saveGuardianPIN("1234")
        container.parentalControlsPreferences.setRole(.pinToLeave, serverID: "A", userID: "kid")
        container.migrateUnmarkedProfilesToEntryLocked()

        container.parentalControlsPreferences.setRole(.open, serverID: "A", userID: "dad")
        container.migrateUnmarkedProfilesToEntryLocked()

        #expect(container.parentalControlsPreferences.role(serverID: "A", userID: "dad") == .open)
    }
}

/// The reason a challenge carries is also the door it stands at: only entering a profile can be
/// opened by anything other than the Guardian PIN.
@MainActor
struct PINReasonDoorTests {

    @Test("Only entering a profile is that profile's door")
    func doorMapping() {
        let ref = ProfileRef(serverID: "A", userID: "family")
        #expect(ParentalGatePolicy.door(for: .enterProfile(ref)) == .profile(ref))
        #expect(ParentalGatePolicy.door(for: .switchProfile) == .guardian)
        #expect(ParentalGatePolicy.door(for: .logout) == .guardian)
        #expect(ParentalGatePolicy.door(for: .serverManagement) == .guardian)
        #expect(ParentalGatePolicy.door(for: .openParentalSettings) == .guardian)
    }

    @Test("An entry-locked target carries its own ref, an open one does not need it")
    func reasonCarriesTheTarget() {
        let ref = ProfileRef(serverID: "A", userID: "family")
        #expect(ParentalGatePolicy.reason(forActivating: .pinToEnter, ref: ref) == .enterProfile(ref))
        #expect(ParentalGatePolicy.reason(forActivating: .open, ref: ref) == .switchProfile)
        #expect(ParentalGatePolicy.reason(forActivating: .pinToLeave, ref: ref) == .switchProfile)
    }
}

/// A seat proves something about its occupant only where the Guardian PIN is the only way in.
@MainActor
struct SessionActionTrustTests {

    @Test("An entry lock the Guardian PIN alone opens is trusted")
    func guardianOnlyEntryLockIsTrusted() {
        #expect(!ParentalGatePolicy.sessionActionRequiresPIN(activeRole: .pinToEnter,
                                                            activeHasOwnPIN: false))
    }

    @Test("An entry lock with its own PIN is not")
    func ownPINIsNotTrusted() {
        // The child knows the family PIN, so the seat proves nothing about who is in it.
        #expect(ParentalGatePolicy.sessionActionRequiresPIN(activeRole: .pinToEnter,
                                                           activeHasOwnPIN: true))
    }

    @Test("Open and locked-in seats are gated as before")
    func otherRolesUnchanged() {
        for hasOwn in [false, true] {
            #expect(ParentalGatePolicy.sessionActionRequiresPIN(activeRole: .open,
                                                               activeHasOwnPIN: hasOwn))
            #expect(ParentalGatePolicy.sessionActionRequiresPIN(activeRole: .pinToLeave,
                                                               activeHasOwnPIN: hasOwn))
        }
    }

    @Test("With no own PIN anywhere the predicate is the one it replaced")
    func matchesTheOldPredicateWithoutOwnPINs() {
        for role in ProfileLockRole.allCases {
            #expect(ParentalGatePolicy.sessionActionRequiresPIN(activeRole: role,
                                                               activeHasOwnPIN: false)
                    == (role != .pinToEnter))
        }
    }
}
