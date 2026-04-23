import Foundation
import Observation

/// User-facing preferences that control what happens on app launch
/// when multiple profiles have been remembered for the active
/// server. UserDefaults-backed — none of this is sensitive (just
/// which profile ID to auto-pick and whether to show the picker).
@Observable
@MainActor
final class AuthPreferences {

    enum LaunchBehavior: String, CaseIterable, Sendable {
        /// Show the remembered-profiles picker on every cold launch.
        /// Matches the Netflix-style "Who's watching?" feel.
        case showPicker
        /// Skip the picker and restore `defaultUserID` directly.
        /// If the default ID is no longer remembered (user was
        /// forgotten), we silently fall back to the picker.
        case useDefault
    }

    // MARK: - Keys

    private enum Keys {
        static let launchBehavior = "auth.launchBehavior"
        static let defaultUserID = "auth.defaultUserID"
    }

    // MARK: - State

    var launchBehavior: LaunchBehavior {
        didSet { store.set(launchBehavior.rawValue, forKey: Keys.launchBehavior) }
    }

    /// Jellyfin user ID to restore when `launchBehavior == .useDefault`.
    /// Nil means "no default set yet" — the picker shows regardless
    /// of launch behavior in that case.
    var defaultUserID: String? {
        didSet {
            if let defaultUserID, !defaultUserID.isEmpty {
                store.set(defaultUserID, forKey: Keys.defaultUserID)
            } else {
                store.removeObject(forKey: Keys.defaultUserID)
            }
        }
    }

    // MARK: - Init

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        let raw = store.string(forKey: Keys.launchBehavior) ?? LaunchBehavior.showPicker.rawValue
        self.launchBehavior = LaunchBehavior(rawValue: raw) ?? .showPicker
        self.defaultUserID = store.string(forKey: Keys.defaultUserID)
    }
}
