import Testing
@testable import Sodalite

struct GuardianPINRecoveryCandidatesTests {
    private func pick(_ roles: [String: ProfileLockRole]) -> [String] {
        GuardianPINRecoveryCandidates
            .candidates(roles.keys.sorted(), role: { roles[$0] ?? .open }, hasOwnPIN: { _ in false })
    }

    /// A household with entry locks: only a profile a PIN holder may enter proves guardianship.
    @Test func entryLockedProfilesWinWhenPresent() {
        #expect(pick(["dad": .pinToEnter, "family": .pinToEnter, "kid": .open, "locked": .pinToLeave])
                == ["dad", "family"])
    }

    /// Today's rule survives untouched for installs that never set an entry lock.
    @Test func withoutEntryLocksTheOpenProfilesRemainCandidates() {
        #expect(pick(["dad": .open, "kid": .pinToLeave]) == ["dad"])
    }

    /// A leave-locked profile is the child's, in either branch.
    @Test func leaveLockedProfilesAreNeverCandidates() {
        #expect(pick(["kid": .pinToLeave]).isEmpty)
        #expect(pick(["kid": .pinToLeave, "teen": .pinToLeave]).isEmpty)
    }

    @Test func anEmptyListStaysEmpty() {
        #expect(pick([:]).isEmpty)
    }
}

/// Recovery asks for the password of the most privileged class of profile the household has, and an
/// own PIN demotes a profile out of the top class: it opens with a secret typed in the open.
struct RecoveryTierTests {

    private struct P: Equatable {
        let name: String
        let role: ProfileLockRole
        let ownPIN: Bool
    }

    private func pick(_ profiles: [P]) -> [String] {
        GuardianPINRecoveryCandidates
            .candidates(profiles, role: { $0.role }, hasOwnPIN: { $0.ownPIN })
            .map(\.name)
    }

    @Test("Guardian-only entry locks win over ones with their own PIN")
    func tierOneWins() {
        #expect(pick([
            P(name: "kid", role: .open, ownPIN: false),
            P(name: "family", role: .pinToEnter, ownPIN: true),
            P(name: "dad", role: .pinToEnter, ownPIN: false)
        ]) == ["dad"])
    }

    @Test("A household where every entry lock has its own PIN still has candidates")
    func tierTwoWins() {
        #expect(pick([
            P(name: "kid", role: .open, ownPIN: false),
            P(name: "family", role: .pinToEnter, ownPIN: true),
            P(name: "dad", role: .pinToEnter, ownPIN: true)
        ]) == ["family", "dad"])
    }

    @Test("With no entry lock at all the old rule stands")
    func tierThreeWins() {
        #expect(pick([
            P(name: "kid", role: .pinToLeave, ownPIN: false),
            P(name: "dad", role: .open, ownPIN: false)
        ]) == ["dad"])
    }
}

/// Pressing "Forgot PIN?" twice has to walk out of a household where every entry-locked profile
/// carries its own PIN and the Guardian PIN was forgotten as well.
struct PINRecoveryOutcomeTests {

    @Test("At a profile door with its own PIN, that PIN is what gets cleared")
    func clearsTheOwnPIN() {
        let ref = ProfileRef(serverID: "A", userID: "family")
        #expect(PINRecoveryOutcome.forDoor(reason: .enterProfile(ref), hasOwnPIN: { _ in true })
                == .clearOwnPIN(ref))
    }

    @Test("At a profile door the Guardian PIN alone opens, the Guardian PIN is reset")
    func resetsTheGuardianPIN() {
        let ref = ProfileRef(serverID: "A", userID: "dad")
        #expect(PINRecoveryOutcome.forDoor(reason: .enterProfile(ref), hasOwnPIN: { _ in false })
                == .collectNewGuardianPIN)
    }

    @Test("Every Guardian door resets the Guardian PIN")
    func guardianDoorsResetGuardian() {
        for reason in [PINReason.switchProfile, .logout, .serverManagement, .openParentalSettings] {
            #expect(PINRecoveryOutcome.forDoor(reason: reason, hasOwnPIN: { _ in true })
                    == .collectNewGuardianPIN)
        }
    }
}
