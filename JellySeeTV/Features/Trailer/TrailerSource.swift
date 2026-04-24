import Foundation

/// The resolved trailer origin for a media item. Callers branch on
/// this to decide whether to hand off to our own player (`.local`)
/// or to the external YouTube app with a QR fallback (`.youtube`).
enum TrailerSource: Sendable, Equatable {
    /// A Jellyfin item pointing at a trailer file on disk. Played
    /// through the same AetherEngine pipeline as normal content —
    /// full-quality, no external apps involved.
    case local(JellyfinItem)

    /// YouTube video identifier + canonical watch URL. Caller tries
    /// to open it in the YouTube app first; if `UIApplication.open`
    /// comes back false, falls back to a QR-code sheet so the user
    /// can scan with a phone.
    case youtube(videoKey: String, watchURL: URL, title: String?)

    case unavailable
}

/// Helper to canonicalize anything YouTube-shaped into a
/// `https://youtu.be/<key>` URL that both the YouTube tvOS app and
/// phone browsers recognise as the same video.
struct YouTubeURL: Equatable, Sendable {
    let videoKey: String

    /// Universal-link form — preferred target for
    /// UIApplication.shared.open so the YouTube TV app can pick it
    /// up via its associated-domains config.
    var watchURL: URL {
        // force-unwrap is safe: videoKey is non-empty and
        // URL-literal-safe by construction.
        URL(string: "https://youtu.be/\(videoKey)")!
    }

    /// Legacy URL scheme the YouTube app has historically claimed.
    /// Used as a second-try when the Universal Link doesn't resolve.
    var appSchemeURL: URL? {
        URL(string: "youtube://\(videoKey)")
    }

    /// Build from a raw TMDB/Jellyfin key string (e.g. "dQw4w9WgXcQ").
    static func from(key: String) -> YouTubeURL? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return YouTubeURL(videoKey: trimmed)
    }

    /// Pull a YouTube key out of any Jellyfin remote-trailer URL
    /// form we've seen in the wild:
    ///   https://www.youtube.com/watch?v=KEY
    ///   https://youtu.be/KEY
    ///   https://www.youtube.com/embed/KEY
    static func parse(from raw: String) -> YouTubeURL? {
        guard let url = URL(string: raw), let host = url.host else { return nil }

        if host.contains("youtu.be") {
            let key = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return from(key: key)
        }
        if host.contains("youtube.com") {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let key = comps.queryItems?.first(where: { $0.name == "v" })?.value {
                return from(key: key)
            }
            if url.path.hasPrefix("/embed/") {
                return from(key: String(url.path.dropFirst("/embed/".count)))
            }
        }
        return nil
    }
}
