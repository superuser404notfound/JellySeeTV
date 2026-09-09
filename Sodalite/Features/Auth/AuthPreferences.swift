import Foundation
import Observation

/// Launch behavior for multi-profile servers. UserDefaults-backed (no secrets, just IDs + picker toggle).
@Observable
@MainActor
final class AuthPreferences {

    enum LaunchBehavior: String, CaseIterable, Sendable {
        case showPicker
        /// Restore `defaultUserID` directly; silently falls back to the picker if that ID is no longer remembered.
        case useDefault
    }

    /// How long the app must sit in the background before the profile picker reappears
    /// on return (issue #41). Only meaningful while launchBehavior == .showPicker.
    enum ProfileRepromptInterval: String, CaseIterable, Sendable {
        case off
        case immediately
        case after30s
        case after1min
        case after5min
        case after15min
        case after60min

        /// Minimum background duration before reprompting; nil disables the reprompt.
        var threshold: Duration? {
            switch self {
            case .off: nil
            case .immediately: .zero
            case .after30s: .seconds(30)
            case .after1min: .seconds(60)
            case .after5min: .seconds(300)
            case .after15min: .seconds(900)
            case .after60min: .seconds(3600)
            }
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let launchBehavior = "auth.launchBehavior"
        /// Retired single-slot pin: a default profile only means anything inside one server's profile list, so one slot let pinning on server B silently unpin server A.
        static let legacyDefaultUserID = "auth.defaultUserID"
        static func defaultUserID(serverID: String) -> String {
            "auth.defaultUserID.\(serverID)"
        }
        static let defaultServerID = "auth.defaultServerID"
        static let profileReprompt = "auth.profileReprompt"
        static let forgottenServers = "auth.forgottenServers"
    }

    // MARK: - State

    var launchBehavior: LaunchBehavior {
        didSet { store.set(launchBehavior.rawValue, forKey: Keys.launchBehavior) }
    }

    var profileReprompt: ProfileRepromptInterval {
        didSet { store.set(profileReprompt.rawValue, forKey: Keys.profileReprompt) }
    }

    /// Bumped on every write below. A method is invisible to `@Observable`, so the accessor reads this to register the dependency for the enclosing view body instead.
    private(set) var defaultUserIDRevision: Int = 0

    /// The same, for the UserDefaults-backed `forgottenServers` map.
    private(set) var forgottenServersRevision: Int = 0

    /// The profile pinned as default on one server. Nil means none: the picker shows regardless of launch behavior.
    func defaultUserID(serverID: String) -> String? {
        _ = defaultUserIDRevision
        return store.string(forKey: Keys.defaultUserID(serverID: serverID))
    }

    func setDefaultUserID(_ userID: String?, serverID: String) {
        if let userID, !userID.isEmpty {
            store.set(userID, forKey: Keys.defaultUserID(serverID: serverID))
        } else {
            store.removeObject(forKey: Keys.defaultUserID(serverID: serverID))
        }
        defaultUserIDRevision &+= 1
    }

    /// One-time move of the retired single-slot pin onto the server it must have belonged to (the pinned default server, else the active one). Deletes the old entry either way, so it can never resurface on a third server.
    func migrateLegacyDefaultUserID(toServerID serverID: String?) {
        guard let legacy = store.string(forKey: Keys.legacyDefaultUserID) else { return }
        store.removeObject(forKey: Keys.legacyDefaultUserID)
        guard let serverID,
              store.string(forKey: Keys.defaultUserID(serverID: serverID)) == nil
        else { return }
        setDefaultUserID(legacy, serverID: serverID)
    }

    /// Servers removed on purpose, keyed by server id with the moment of removal.
    ///
    /// A removal has to travel as a removal: a server record is republished in full by any device
    /// that touches it, so "my list is shorter" reads the same as "I have not heard yet", and the
    /// deleted server came straight back from whichever device republished it first.
    var forgottenServers: [String: Date] {
        get {
            // Same trick as defaultUserIDRevision: the value lives in UserDefaults, so there is no
            // stored property for @Observable to track, and the sync layer arms its observation by
            // reading the payload. Touching the counter here is what registers the dependency.
            _ = forgottenServersRevision
            let raw = (store.dictionary(forKey: Keys.forgottenServers) as? [String: Double]) ?? [:]
            return raw.mapValues(Date.init(timeIntervalSince1970:))
        }
        set {
            forgottenServersRevision &+= 1
            if newValue.isEmpty {
                store.removeObject(forKey: Keys.forgottenServers)
            } else {
                store.set(newValue.mapValues(\.timeIntervalSince1970), forKey: Keys.forgottenServers)
            }
        }
    }

    /// Server auto-promoted to active on cold launch. Nil keeps the most-recently-used; cleared when the server is removed.
    var defaultServerID: String? {
        didSet {
            if let defaultServerID, !defaultServerID.isEmpty {
                store.set(defaultServerID, forKey: Keys.defaultServerID)
            } else {
                store.removeObject(forKey: Keys.defaultServerID)
            }
        }
    }

    // MARK: - Init

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        let raw = store.string(forKey: Keys.launchBehavior) ?? LaunchBehavior.showPicker.rawValue
        self.launchBehavior = LaunchBehavior(rawValue: raw) ?? .showPicker
        let repromptRaw = store.string(forKey: Keys.profileReprompt) ?? ProfileRepromptInterval.off.rawValue
        self.profileReprompt = ProfileRepromptInterval(rawValue: repromptRaw) ?? .off
        self.defaultServerID = store.string(forKey: Keys.defaultServerID)
    }
}
