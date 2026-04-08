import Foundation

/// Known streaming provider / network names to filter Jellyfin studios.
/// Matched case-insensitively with exact match only.
enum StreamingProviders {
    static let known: Set<String> = [
        // Global Streaming
        "Netflix",
        "Prime Video",
        "Amazon Prime Video",
        "Amazon Studios",
        "Disney+",
        "Disney Plus",
        "Walt Disney Pictures",
        "Walt Disney Studios",
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
        "YouTube",
        "YouTube Premium",
        "YouTube Originals",

        // Anime
        "Crunchyroll",
        "Funimation",

        // US Networks / Streaming
        "ABC",
        "ABC (US)",
        "NBC",
        "CBS",
        "The CW",
        "The WB",
        "Showtime",
        "Starz",
        "AMC",
        "AMC+",
        "Nickelodeon",
        "Lionsgate",
        "Lionsgate+",
        "MGM+",
        "Discovery+",
        "Discovery Plus",
        "BritBox",
        "Tubi",
        "Pluto TV",
        "Freevee",
        "MUBI",
        "Shudder",

        // European
        "Sky",
        "Sky Studios",
        "Canal+",
        "ARD",
        "Das Erste",
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
        "Viaplay",
        "NRK",
        "SVT",
        "DR",

        // Japanese
        "Fuji TV",
        "TBS (JP)",
        "NHK",
    ]

    static func isProvider(_ studioName: String) -> Bool {
        let lowered = studioName.lowercased()
        return known.contains { $0.lowercased() == lowered }
    }
}
