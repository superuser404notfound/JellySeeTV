import Foundation
import Observation
import AetherEngine

/// Device-local playback preferences. Backed by `UserDefaults` so they
/// survive app restarts; not synced via CloudSyncService because most of
/// these are user-interaction tuning, not content choices.
///
/// Read/write from anywhere through `DependencyContainer.playbackPreferences`.
/// The class is `@Observable`, so SwiftUI views update automatically when a
/// setting changes.
@Observable
@MainActor
final class PlaybackPreferences {

    // MARK: - Keys

    private enum Keys {
        static let autoplayNextEpisode = "playback.autoplayNextEpisode"
        static let nextEpisodeCountdownSeconds = "playback.nextEpisodeCountdownSeconds"
        static let skipIntervalSeconds = "playback.skipIntervalSeconds"
        static let preferredAudioLanguage = "playback.preferredAudioLanguage"
        static let preferredSubtitleLanguage = "playback.preferredSubtitleLanguage"
        static let autoSkipIntro = "playback.autoSkipIntro"
        static let audioProcessing = "playback.audioProcessing"
        static let dialogBoost = "playback.dialogBoost"
    }

    // MARK: - Allowed Values

    /// 0 = disabled (countdown doesn't appear), otherwise countdown seconds.
    static let countdownChoices: [Int] = [0, 5, 10, 15]
    static let skipIntervalChoices: [Int] = [5, 10, 15, 30]
    static let languageChoices: [LanguageChoice] = [
        LanguageChoice(code: nil,    short: "Auto", titleKey: "settings.playback.language.auto"),
        LanguageChoice(code: "deu",  short: "DE",   titleKey: "settings.playback.language.deu"),
        LanguageChoice(code: "eng",  short: "EN",   titleKey: "settings.playback.language.eng"),
        LanguageChoice(code: "fra",  short: "FR",   titleKey: "settings.playback.language.fra"),
        LanguageChoice(code: "spa",  short: "ES",   titleKey: "settings.playback.language.spa"),
        LanguageChoice(code: "ita",  short: "IT",   titleKey: "settings.playback.language.ita"),
        LanguageChoice(code: "jpn",  short: "JA",   titleKey: "settings.playback.language.jpn"),
        LanguageChoice(code: "zho",  short: "ZH",   titleKey: "settings.playback.language.zho"),
    ]

    struct LanguageChoice: Hashable, Sendable {
        /// ISO 639-2/B code as Jellyfin uses it (e.g. "deu", "eng"),
        /// or nil for "use the stream's default / current logic".
        let code: String?
        /// Short label for the chip UI ("DE", "EN", "Auto").
        let short: String
        /// Localization key for the long name ("Deutsch", "Englisch", …).
        let titleKey: String
    }

    // MARK: - Properties

    var autoplayNextEpisode: Bool {
        didSet { store.set(autoplayNextEpisode, forKey: Keys.autoplayNextEpisode) }
    }

    var autoSkipIntro: Bool {
        didSet { store.set(autoSkipIntro, forKey: Keys.autoSkipIntro) }
    }

    var nextEpisodeCountdownSeconds: Int {
        didSet { store.set(nextEpisodeCountdownSeconds, forKey: Keys.nextEpisodeCountdownSeconds) }
    }

    var skipIntervalSeconds: Int {
        didSet { store.set(skipIntervalSeconds, forKey: Keys.skipIntervalSeconds) }
    }

    var preferredAudioLanguage: String? {
        didSet { store.set(preferredAudioLanguage, forKey: Keys.preferredAudioLanguage) }
    }

    var preferredSubtitleLanguage: String? {
        didSet { store.set(preferredSubtitleLanguage, forKey: Keys.preferredSubtitleLanguage) }
    }

    /// Default Night Mode applied at the start of every playback session.
    /// User can still override per-film from the in-player audio button.
    var audioProcessing: AudioProcessingMode {
        didSet { store.set(audioProcessing.rawValue, forKey: Keys.audioProcessing) }
    }

    /// Default Dialog Boost applied at the start of every playback session.
    var dialogBoost: Bool {
        didSet { store.set(dialogBoost, forKey: Keys.dialogBoost) }
    }

    // MARK: - Init

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        self.autoplayNextEpisode = store.object(forKey: Keys.autoplayNextEpisode) as? Bool ?? true
        self.autoSkipIntro = store.object(forKey: Keys.autoSkipIntro) as? Bool ?? false
        self.nextEpisodeCountdownSeconds = store.object(forKey: Keys.nextEpisodeCountdownSeconds) as? Int ?? 10
        self.skipIntervalSeconds = store.object(forKey: Keys.skipIntervalSeconds) as? Int ?? 10
        self.preferredAudioLanguage = store.string(forKey: Keys.preferredAudioLanguage)
        self.preferredSubtitleLanguage = store.string(forKey: Keys.preferredSubtitleLanguage)
        let storedMode = store.string(forKey: Keys.audioProcessing).flatMap(AudioProcessingMode.init(rawValue:))
        self.audioProcessing = storedMode ?? .off
        self.dialogBoost = store.object(forKey: Keys.dialogBoost) as? Bool ?? false
    }
}
