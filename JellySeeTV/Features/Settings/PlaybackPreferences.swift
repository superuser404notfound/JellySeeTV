import Foundation
import Observation

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
        static let autoSkipOutro = "playback.autoSkipOutro"
        static let autoSubtitleForForeignAudio = "playback.autoSubtitleForForeignAudio"
    }

    // MARK: - Allowed Values

    /// 0 = disabled (countdown doesn't appear), otherwise countdown seconds.
    static let countdownChoices: [Int] = [0, 5, 10, 15]
    static let skipIntervalChoices: [Int] = [5, 10, 15, 30]

    /// Shared language options — alphabetical by display name. ISO 639-2/B
    /// bibliographic codes (Jellyfin's convention: "deu" not "ger", "cze"
    /// not "ces", etc.).
    private static let baseLanguages: [LanguageChoice] = [
        LanguageChoice(code: "ara", short: "AR",  titleKey: "settings.playback.language.ara"),
        LanguageChoice(code: "chi", short: "ZH",  titleKey: "settings.playback.language.zho"),
        LanguageChoice(code: "cze", short: "CS",  titleKey: "settings.playback.language.ces"),
        LanguageChoice(code: "dan", short: "DA",  titleKey: "settings.playback.language.dan"),
        LanguageChoice(code: "dut", short: "NL",  titleKey: "settings.playback.language.nld"),
        LanguageChoice(code: "eng", short: "EN",  titleKey: "settings.playback.language.eng"),
        LanguageChoice(code: "fin", short: "FI",  titleKey: "settings.playback.language.fin"),
        LanguageChoice(code: "fre", short: "FR",  titleKey: "settings.playback.language.fra"),
        LanguageChoice(code: "ger", short: "DE",  titleKey: "settings.playback.language.deu"),
        LanguageChoice(code: "gre", short: "EL",  titleKey: "settings.playback.language.ell"),
        LanguageChoice(code: "heb", short: "HE",  titleKey: "settings.playback.language.heb"),
        LanguageChoice(code: "hin", short: "HI",  titleKey: "settings.playback.language.hin"),
        LanguageChoice(code: "hun", short: "HU",  titleKey: "settings.playback.language.hun"),
        LanguageChoice(code: "ind", short: "ID",  titleKey: "settings.playback.language.ind"),
        LanguageChoice(code: "ita", short: "IT",  titleKey: "settings.playback.language.ita"),
        LanguageChoice(code: "jpn", short: "JA",  titleKey: "settings.playback.language.jpn"),
        LanguageChoice(code: "kor", short: "KO",  titleKey: "settings.playback.language.kor"),
        LanguageChoice(code: "nor", short: "NO",  titleKey: "settings.playback.language.nor"),
        LanguageChoice(code: "pol", short: "PL",  titleKey: "settings.playback.language.pol"),
        LanguageChoice(code: "por", short: "PT",  titleKey: "settings.playback.language.por"),
        LanguageChoice(code: "rum", short: "RO",  titleKey: "settings.playback.language.ron"),
        LanguageChoice(code: "rus", short: "RU",  titleKey: "settings.playback.language.rus"),
        LanguageChoice(code: "spa", short: "ES",  titleKey: "settings.playback.language.spa"),
        LanguageChoice(code: "swe", short: "SV",  titleKey: "settings.playback.language.swe"),
        LanguageChoice(code: "tha", short: "TH",  titleKey: "settings.playback.language.tha"),
        LanguageChoice(code: "tur", short: "TR",  titleKey: "settings.playback.language.tur"),
        LanguageChoice(code: "ukr", short: "UK",  titleKey: "settings.playback.language.ukr"),
        LanguageChoice(code: "vie", short: "VI",  titleKey: "settings.playback.language.vie"),
    ]

    /// Audio pref dropdown — "Auto" first, then the shared alphabetical list.
    static var audioLanguageChoices: [LanguageChoice] {
        [LanguageChoice(code: nil, short: "Auto", titleKey: "settings.playback.language.auto")]
            + baseLanguages
    }

    /// Subtitle pref dropdown — "Off" first (renamed from "Auto" to avoid
    /// confusion with audio: Auto for audio means "pick a sensible track,"
    /// for subtitles it reads as "I don't know, figure it out," when the
    /// user's intent is actually "don't show any subtitles").
    static var subtitleLanguageChoices: [LanguageChoice] {
        [LanguageChoice(code: nil, short: "Off", titleKey: "settings.playback.language.off")]
            + baseLanguages
    }

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

    var autoSkipOutro: Bool {
        didSet { store.set(autoSkipOutro, forKey: Keys.autoSkipOutro) }
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

    /// Auto-enable subtitles when the playing audio track isn't in the
    /// user's preferred audio language. Default ON because that mirrors
    /// the streaming-app convention (Netflix et al.) — if the user wants
    /// German and the episode only has English, they almost always want
    /// German subs on top. Flip off for users who don't want subs ever.
    var autoSubtitleForForeignAudio: Bool {
        didSet { store.set(autoSubtitleForForeignAudio, forKey: Keys.autoSubtitleForForeignAudio) }
    }

    // MARK: - Init

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        self.autoplayNextEpisode = store.object(forKey: Keys.autoplayNextEpisode) as? Bool ?? true
        self.autoSkipIntro = store.object(forKey: Keys.autoSkipIntro) as? Bool ?? false
        self.autoSkipOutro = store.object(forKey: Keys.autoSkipOutro) as? Bool ?? false
        self.nextEpisodeCountdownSeconds = store.object(forKey: Keys.nextEpisodeCountdownSeconds) as? Int ?? 10
        self.skipIntervalSeconds = store.object(forKey: Keys.skipIntervalSeconds) as? Int ?? 10
        self.preferredAudioLanguage = store.string(forKey: Keys.preferredAudioLanguage)
        self.preferredSubtitleLanguage = store.string(forKey: Keys.preferredSubtitleLanguage)
        self.autoSubtitleForForeignAudio = store.object(forKey: Keys.autoSubtitleForForeignAudio) as? Bool ?? true
    }
}
