import Foundation

/// One spelling for every season/episode line the app draws: `S1, E5 · Title`.
///
/// The token stays verbatim across locales (`S1, E5` is universal in streaming UIs), which is why
/// nothing here goes through the string catalog. The separator is the middle dot Sodalite already
/// joins genres, runtimes and breadcrumbs with, so the episode line reads in the same grammar as
/// every other metadata line.
///
/// `nonisolated` for the same reason as `TopShelfProgress`: the app targets default to MainActor
/// isolation, the extension defaults to nonisolated, and both compile this file.
enum EpisodeMetadataFormatter {
    nonisolated static let separator = " · "

    /// `S1, E5` / `S1` / `E5` / `""`, by whichever numbers the item carries. Empty rather than nil
    /// so a caller that only wants the token keeps its existing `isEmpty` check.
    ///
    /// A season with no episode number degrades to `S1`, never `S1, `: Jellyfin returns
    /// `ParentIndexNumber` without `IndexNumber` for specials and unnumbered entries.
    nonisolated static func seasonEpisode(season: Int?, episode: Int?) -> String {
        var parts: [String] = []
        if let season { parts.append("S\(season)") }
        if let episode { parts.append("E\(episode)") }
        return parts.joined(separator: ", ")
    }

    /// `[series] · [token] · [title]`, skipping every segment that is missing or empty:
    /// `S1, E5 · Title`, `E5 · Title`, `Friends · S3, E15 · Title`, `Title`, `""`.
    nonisolated static func label(seriesName: String? = nil,
                                  season: Int?,
                                  episode: Int?,
                                  title: String?) -> String {
        [seriesName, seasonEpisode(season: season, episode: episode), title]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    /// The line UNDER a series title, where the series name is already on screen above it: the
    /// token plus the episode's own title, with a title that merely repeats the series name dropped.
    /// Some EPG sources set both to the show, and the two lines would then read "Friends" over
    /// "S3, E15 · Friends" (Sodalite#104).
    nonisolated static func episodeLine(under seriesName: String?,
                                        season: Int?,
                                        episode: Int?,
                                        title: String?) -> String {
        label(season: season, episode: episode, title: title == seriesName ? nil : title)
    }

    /// The Live-TV cascade: episode title, then series name, then the bare token, dropping any
    /// value equal to `header` (the program name) because some EPG providers set them equal and
    /// the guide would render the same string twice.
    ///
    /// Optional rather than empty because both guide surfaces render the subtitle conditionally.
    nonisolated static func programLabel(season: Int?,
                                         episode: Int?,
                                         episodeTitle: String?,
                                         seriesName: String?,
                                         header: String) -> String? {
        // Unlike `label`, the EPG token needs both halves: a lone "S4" beside a program name
        // identifies nothing, and no guide surface supplies the missing half from context.
        let numbered = season != nil && episode != nil
        let season = numbered ? season : nil
        let episode = numbered ? episode : nil

        if let episodeTitle, episodeTitle != header {
            return nonEmpty(label(season: season, episode: episode, title: episodeTitle))
        }
        if let seriesName, seriesName != header {
            return nonEmpty(label(seriesName: seriesName, season: season, episode: episode,
                                  title: nil))
        }
        return nonEmpty(seasonEpisode(season: season, episode: episode))
    }

    nonisolated private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
