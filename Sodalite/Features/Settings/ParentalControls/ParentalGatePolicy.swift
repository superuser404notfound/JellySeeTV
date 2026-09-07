import Foundation

/// Pure gate decisions for the Guardian PIN. The container holds the stores and the active-session
/// pointers; everything that is a judgement lives here so it can be asserted without them.
enum ParentalGatePolicy {

    /// Whether activating a profile of `targetRole` costs the PIN, given the role of the profile
    /// that is active right now.
    ///
    /// There is no cold-start term any more. A lock is a property of the door, and before #105 the
    /// cold-start prompt was how an unmarked profile expressed one; the migration reads those as
    /// `pinToEnter`, which says the same thing at every hour. At a cold start there is no session,
    /// so `activeRole` is `.open` and only the door decides.
    static func gateRequiredForActivating(targetRole: ProfileLockRole,
                                          activeRole: ProfileLockRole) -> Bool {
        switch targetRole {
        case .pinToLeave:
            // Walking into a locked-in profile is free; the lock is on the way out.
            return false
        case .pinToEnter:
            return true
        case .open:
            // Open means open, except as the far side of somebody else's leave-lock: this is the
            // branch that actually enforces pinToLeave, so it cannot go free.
            return activeRole == .pinToLeave
        }
    }

    /// Whether a session-scoped escape (logout, server management, tabs, Seerr, iCloud, support,
    /// the profile screen) costs the PIN.
    ///
    /// Trust is a property of the door, never of the key that was used. Only a profile the Guardian
    /// PIN ALONE opens carries an occupant who has proven guardianship: an open profile is reachable
    /// by anyone, a locked-in one is where the child sits, and one with its own PIN is opened by a
    /// secret the household types in front of everybody. Reading back which key was actually entered
    /// would spare a parent one prompt and hand the whole set to the next person the remote reaches.
    /// The one screen that can disable all of it asks regardless (see SettingsView).
    static func sessionActionRequiresPIN(activeRole: ProfileLockRole,
                                         activeHasOwnPIN: Bool) -> Bool {
        !(activeRole == .pinToEnter && !activeHasOwnPIN)
    }

    /// `switchProfile` is raised when LEAVING a leave-locked profile, so it belongs to the active
    /// profile's exit lock and never to the target's.
    static func reason(forActivating targetRole: ProfileLockRole, ref: ProfileRef) -> PINReason {
        targetRole == .pinToEnter ? .enterProfile(ref) : .switchProfile
    }

    /// The lock a challenge for `reason` is made against. Every reason but entering a profile is the
    /// Guardian's own door, which is what keeps an own PIN out of every privileged action.
    static func door(for reason: PINReason) -> PINDoor {
        switch reason {
        case .enterProfile(let ref): .profile(ref)
        case .switchProfile, .logout, .serverManagement, .openParentalSettings: .guardian
        }
    }
}
