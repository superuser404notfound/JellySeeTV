import Foundation
import Observation
import SwiftUI

/// Cosmetic choices unlocked by the Supporter Pack. Non-supporters are
/// pinned to `.system` defaults at read time — the stored value stays
/// intact so we don't wipe a selection after a refund-then-repurchase
/// cycle.
///
/// Backed by `UserDefaults`, not the Keychain — none of this is sensitive
/// and losing the preference on wipe is fine.
@Observable
@MainActor
final class AppearancePreferences {

    // MARK: - Accent

    enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
        case system   // Default, free for everyone
        case gold
        case rose
        case amethyst
        case mint
        case crimson

        var id: String { rawValue }

        /// Localized display name. Resolved inside the enum so both
        /// arguments to `String(localized:defaultValue:)` stay as
        /// compile-time string literals — the initializer can't accept
        /// runtime `String.LocalizationValue` values.
        var title: String {
            switch self {
            case .system:
                String(localized: "appearance.accent.system",   defaultValue: "System Blue")
            case .gold:
                String(localized: "appearance.accent.gold",     defaultValue: "Gold")
            case .rose:
                String(localized: "appearance.accent.rose",     defaultValue: "Rose")
            case .amethyst:
                String(localized: "appearance.accent.amethyst", defaultValue: "Amethyst")
            case .mint:
                String(localized: "appearance.accent.mint",     defaultValue: "Mint")
            case .crimson:
                String(localized: "appearance.accent.crimson",  defaultValue: "Crimson")
            }
        }

        /// Hex chosen to work against the dark Liquid-Glass backdrop —
        /// punchy but not neon. Swatches render straight from these.
        var color: Color {
            switch self {
            case .system:   .accentColor
            case .gold:     Color(red: 0.98, green: 0.79, blue: 0.35)
            case .rose:     Color(red: 0.99, green: 0.57, blue: 0.70)
            case .amethyst: Color(red: 0.69, green: 0.50, blue: 0.95)
            case .mint:     Color(red: 0.40, green: 0.87, blue: 0.70)
            case .crimson:  Color(red: 0.94, green: 0.35, blue: 0.40)
            }
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let accentChoice = "appearance.accentChoice"
    }

    // MARK: - State

    var accentChoice: AccentChoice {
        didSet { store.set(accentChoice.rawValue, forKey: Keys.accentChoice) }
    }

    // MARK: - Init

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        let raw = store.string(forKey: Keys.accentChoice) ?? AccentChoice.system.rawValue
        self.accentChoice = AccentChoice(rawValue: raw) ?? .system
    }

    /// Effective tint to apply to the UI. Non-supporters always get
    /// `.system` regardless of a previously stored choice, so downgrade
    /// paths are graceful.
    func effectiveAccent(isSupporter: Bool) -> AccentChoice {
        isSupporter ? accentChoice : .system
    }
}
