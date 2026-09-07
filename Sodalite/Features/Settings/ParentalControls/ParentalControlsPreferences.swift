import Foundation
import Observation

/// One remembered profile, addressed the way the lock model addresses it. Deliberately not
/// `CacheIdentity`: that is the filter cache's scope key and belongs with the cache, and a security
/// type that says "cache" reads wrong at every call site here.
struct ProfileRef: Hashable, Sendable, Identifiable {
    let serverID: String
    let userID: String

    var compositeID: String { "\(serverID):\(userID)" }
    var id: String { compositeID }
}

/// The lock a PIN attempt is made against. Attempts are counted per door, so guessing at one
/// profile cannot lock the household out of the Guardian PIN.
enum PINDoor: Hashable, Sendable {
    case guardian
    case profile(ProfileRef)
}

/// How the Guardian PIN applies to one profile. The two locked roles are mutually exclusive by
/// construction: a profile that costs a PIN to enter gains nothing from costing one to leave,
/// because whoever got in holds the PIN already.
enum ProfileLockRole: String, CaseIterable, Hashable {
    case open
    case pinToEnter
    case pinToLeave
}

/// Per-profile lock roles keyed by composite serverID:userID, held as two sets so the CloudSync payload stays additive; PIN hash lives in keychain (DependencyContainer) not here; RememberedUser blob untouched.
@Observable
@MainActor
final class ParentalControlsPreferences {

    private enum Keys {
        static let protectedProfileIDs = "parental.protectedProfileIDs"
        static let entryLockedProfileIDs = "parental.entryLockedProfileIDs"
    }

    var protectedProfileIDs: Set<String> {
        didSet {
            store.set(protectedProfileIDs.sorted(), forKey: Keys.protectedProfileIDs)
        }
    }

    var entryLockedProfileIDs: Set<String> {
        didSet {
            store.set(entryLockedProfileIDs.sorted(), forKey: Keys.entryLockedProfileIDs)
        }
    }

    var hasAnyLockedProfile: Bool { !protectedProfileIDs.isEmpty || !entryLockedProfileIDs.isEmpty }

    static func compositeID(serverID: String, userID: String) -> String {
        ProfileRef(serverID: serverID, userID: userID).compositeID
    }

    func isProtected(_ ref: ProfileRef) -> Bool {
        protectedProfileIDs.contains(ref.compositeID)
    }

    /// Membership in the leave-lock wins, so a store carrying a key in both sets reads as the
    /// stricter role rather than as something a corruption chose.
    func role(_ ref: ProfileRef) -> ProfileLockRole {
        if protectedProfileIDs.contains(ref.compositeID) { return .pinToLeave }
        if entryLockedProfileIDs.contains(ref.compositeID) { return .pinToEnter }
        return .open
    }

    func setRole(_ role: ProfileLockRole, for ref: ProfileRef) {
        let key = ref.compositeID
        protectedProfileIDs.remove(key)
        entryLockedProfileIDs.remove(key)
        switch role {
        case .open:       break
        case .pinToEnter: entryLockedProfileIDs.insert(key)
        case .pinToLeave: protectedProfileIDs.insert(key)
        }
    }

    func isProtected(serverID: String, userID: String) -> Bool {
        isProtected(ProfileRef(serverID: serverID, userID: userID))
    }

    func role(serverID: String, userID: String) -> ProfileLockRole {
        role(ProfileRef(serverID: serverID, userID: userID))
    }

    func setRole(_ role: ProfileLockRole, serverID: String, userID: String) {
        setRole(role, for: ProfileRef(serverID: serverID, userID: userID))
    }

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        let stored = store.array(forKey: Keys.protectedProfileIDs) as? [String] ?? []
        self.protectedProfileIDs = Set(stored)
        let storedEntry = store.array(forKey: Keys.entryLockedProfileIDs) as? [String] ?? []
        self.entryLockedProfileIDs = Set(storedEntry)
    }
}
