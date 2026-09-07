import Foundation

/// Which profiles' Jellyfin passwords may reset the Guardian PIN.
///
/// Recovery proves guardianship with a password, so it asks for the password of the most privileged
/// class of profile the household actually has. A profile only the Guardian PIN opens is a guardian
/// credential; one that also opens with a PIN typed in front of everybody is a weaker claim but
/// still a locked door; an open profile in a household that HAS entry locks is neither, and
/// accepting it would hand a child the reset.
enum GuardianPINRecoveryCandidates {
    static func candidates<Profile>(_ profiles: [Profile],
                                    role: (Profile) -> ProfileLockRole,
                                    hasOwnPIN: (Profile) -> Bool) -> [Profile] {
        let entryLocked = profiles.filter { role($0) == .pinToEnter }
        let guardianOnly = entryLocked.filter { !hasOwnPIN($0) }
        if !guardianOnly.isEmpty { return guardianOnly }
        if !entryLocked.isEmpty { return entryLocked }
        return profiles.filter { role($0) != .pinToLeave }
    }
}

/// What "Forgot PIN?" repairs, given the door it was pressed at.
///
/// Recovery always repairs the innermost lock in front of the user. That is what lets a household
/// where every entry-locked profile carries its own PIN, and whose Guardian PIN was forgotten too,
/// get back in at all: the first press drops the own PIN, the door is then a Guardian door, and the
/// second press resets the Guardian PIN. Both steps move towards the stricter key, never away.
enum PINRecoveryOutcome: Equatable {
    case clearOwnPIN(ProfileRef)
    case collectNewGuardianPIN

    static func forDoor(reason: PINReason, hasOwnPIN: (ProfileRef) -> Bool) -> PINRecoveryOutcome {
        if case .enterProfile(let ref) = reason, hasOwnPIN(ref) { return .clearOwnPIN(ref) }
        return .collectNewGuardianPIN
    }
}
