import Foundation
import SteelPlayer

/// Formats TrackInfo into localized display strings for the player UI.
///
/// Uses `Locale.current.localizedString(forLanguageCode:)` for language
/// names — automatically localized by Apple's frameworks (e.g. "en" →
/// "Englisch" on a German device, "英語" on Japanese).
///
/// Audio format: "Deutsch · Dolby Digital 5.1"
/// Subtitle format: "Englisch"
enum TrackDisplayFormatter {

    /// Full display name for an audio track.
    /// Example: "Deutsch · Dolby Digital 5.1"
    static func audioDisplayName(for track: TrackInfo) -> String {
        var parts: [String] = []

        // Language name (localized)
        if let lang = languageName(for: track) {
            parts.append(lang)
        }

        // Codec + channels
        let quality = audioQuality(codec: track.codec, channels: track.channels)
        if !quality.isEmpty {
            parts.append(quality)
        }

        if parts.isEmpty {
            return String(localized: "player.track.unknown", defaultValue: "Unknown")
        }
        return parts.joined(separator: " · ")
    }

    /// Display name for a subtitle track.
    /// Example: "Deutsch" or "English (Forced)"
    static func subtitleDisplayName(for track: TrackInfo) -> String {
        // Use title if it contains useful info (e.g. "Forced", "SDH", "Commentary")
        if let title = titleIfUseful(track), let lang = languageName(for: track) {
            return "\(lang) (\(title))"
        }
        return languageName(for: track)
            ?? String(localized: "player.track.unknown", defaultValue: "Unknown")
    }

    /// Short name for the transport bar button label.
    /// Shows language only, no codec info.
    static func shortName(for track: TrackInfo) -> String {
        languageName(for: track) ?? track.name
    }

    // MARK: - Private

    private static func languageName(for track: TrackInfo) -> String? {
        guard let code = track.language, !code.isEmpty else { return nil }
        // Apple's Locale API: returns full language name in the current locale
        if let name = Locale.current.localizedString(forLanguageCode: code) {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return code.uppercased()
    }

    private static func audioQuality(codec: String, channels: Int) -> String {
        let codecDisplay = codecDisplayName(codec)
        let channelDisplay = channelLayout(channels)

        if !codecDisplay.isEmpty && !channelDisplay.isEmpty {
            return "\(codecDisplay) \(channelDisplay)"
        }
        return codecDisplay.isEmpty ? channelDisplay : codecDisplay
    }

    private static func codecDisplayName(_ codec: String) -> String {
        switch codec.lowercased() {
        case "aac": return "AAC"
        case "ac3": return "Dolby Digital"
        case "eac3": return "Dolby Digital+"
        case "truehd": return "Dolby TrueHD"
        case "dts": return "DTS"
        case "dts-hd", "dtshd": return "DTS-HD"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        case "vorbis": return "Vorbis"
        case "mp3", "mp3float": return "MP3"
        case "pcm_s16le", "pcm_s24le", "pcm_s32le": return "PCM"
        default: return codec.uppercased()
        }
    }

    private static func channelLayout(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        case let n where n > 0: return "\(n)ch"
        default: return ""
        }
    }

    /// Returns the track title only if it contains useful metadata
    /// beyond just the language name (e.g. "Forced", "SDH", "Commentary").
    private static func titleIfUseful(_ track: TrackInfo) -> String? {
        guard let title = track.name.nilIfEmpty else { return nil }
        // If the title is just the language code/name, it's not useful
        if let lang = track.language {
            let langName = Locale.current.localizedString(forLanguageCode: lang) ?? ""
            if title.caseInsensitiveCompare(lang) == .orderedSame
                || title.caseInsensitiveCompare(langName) == .orderedSame {
                return nil
            }
        }
        // Check for known useful descriptors
        let useful = ["forced", "sdh", "commentary", "cc", "signs", "songs", "full", "hearing"]
        let lower = title.lowercased()
        if useful.contains(where: { lower.contains($0) }) {
            return title
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
