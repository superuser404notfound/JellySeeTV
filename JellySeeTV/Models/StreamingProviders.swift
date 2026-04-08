import Foundation

/// Known streaming provider names to filter Jellyfin studios against.
/// Names are matched case-insensitively and with contains-check for variations.
enum StreamingProviders {
    static let known: Set<String> = [
        // Major
        "Netflix",
        "Amazon Studios",
        "Amazon Prime Video",
        "Prime Video",
        "Disney+",
        "Disney Plus",
        "Walt Disney Pictures",
        "Apple TV+",
        "Apple TV Plus",
        "Apple Studios",
        "HBO",
        "HBO Max",
        "Max",
        "Hulu",
        "Paramount+",
        "Paramount Plus",
        "Peacock",
        "Crunchyroll",
        "Funimation",

        // European
        "Sky",
        "Sky Studios",
        "Canal+",
        "ARD",
        "ZDF",
        "RTL",
        "RTL+",
        "ProSieben",
        "Sat.1",
        "Joyn",
        "MagentaTV",
        "WOW",
        "BBC",
        "BBC iPlayer",
        "BBC Studios",
        "ITV",
        "Channel 4",
        "France Télévisions",
        "TF1",
        "RAI",
        "Movistar+",
        "Viaplay",
        "NRK",
        "SVT",
        "DR",

        // Other
        "Showtime",
        "Starz",
        "MGM+",
        "Lionsgate+",
        "Discovery+",
        "Discovery Plus",
        "BritBox",
        "Curiosity Stream",
        "CuriosityStream",
        "Tubi",
        "Pluto TV",
        "Roku Channel",
        "Freevee",
        "MUBI",
        "Criterion Channel",
        "Shudder",
        "AMC+",
        "AMC",
        "YouTube Premium",
        "YouTube Originals",
        "Anime on Demand",
        "Wakanim",
        "ADN",
        "Rakuten TV",
        "Videoland",
        "DAZN",
        "ESPN+",
    ]

    /// Check if a studio name matches a known streaming provider.
    /// Uses contains-matching so "Netflix, Inc." matches "Netflix".
    static func isProvider(_ studioName: String) -> Bool {
        let lowered = studioName.lowercased()
        return known.contains { provider in
            let providerLower = provider.lowercased()
            return lowered == providerLower
                || lowered.contains(providerLower)
                || providerLower.contains(lowered)
        }
    }
}
