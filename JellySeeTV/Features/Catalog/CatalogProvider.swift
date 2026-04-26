import Foundation

/// A curated streaming network or movie studio the catalogue can filter
/// by. The list mirrors Jellyseerr web's NetworkSlider / StudioSlider so
/// the discover surface looks the same on both clients without us having
/// to discover networks dynamically (TMDB does not expose a "popular
/// networks" endpoint).
struct CatalogProvider: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    /// TMDB logo path (e.g. "/wwemzKWzjKYJFfCeiB57q3r4Bcm.png").
    /// Rendered through `SeerrImageURL.duotoneLogo` to match Jellyseerr's
    /// monochrome treatment.
    let logoPath: String
    /// Studio names to match against on the Jellyfin side when the
    /// row is used to filter the local library (e.g. on the home
    /// page). Multiple aliases handle the metadata variants TMDB +
    /// Jellyfin libraries collected over the years — Disney+ might
    /// be tagged "Disney+", "Disney Plus", "Walt Disney Pictures",
    /// or simply "Walt Disney Studios" depending on which scraper
    /// stamped the item. Joined with `|` they OR together inside
    /// Jellyfin's Studios query parameter.
    let jellyfinStudioNames: [String]
    /// TMDB watch-provider id for the streaming service this entry
    /// represents. Different from `id` (which is the network/studio
    /// id) — TMDB tracks "this title is on Netflix" with provider
    /// id 8, "on Disney+" with 337, etc. Used to ask Jellyseerr's
    /// `/discover/{movies|tv}?watchProviders=…&watchRegion=…` for
    /// the live list of titles streaming on this service in the
    /// user's region. nil → no smart-filter augmentation, fall back
    /// to studio-name match alone.
    let tmdbWatchProviderID: Int?

    init(
        id: Int,
        name: String,
        logoPath: String,
        jellyfinStudioNames: [String]? = nil,
        tmdbWatchProviderID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
        self.jellyfinStudioNames = jellyfinStudioNames ?? [name]
        self.tmdbWatchProviderID = tmdbWatchProviderID
    }
}

enum CatalogProviders {
    /// Ordered roughly by global subscriber base, top tiers first.
    /// The user almost always wants Netflix / Prime / Disney+ within
    /// the first horizontal swipe, so they sit at the front; broadcast
    /// channels and kids networks sit at the bottom because they're
    /// rarely what someone reaches for when browsing a streaming row.
    /// Within each tier the order is purely curatorial — close enough
    /// to global popularity that the front of the row stays useful
    /// regardless of region.
    static let networks: [CatalogProvider] = [
        // MARK: - Tier 1 — top global SVOD

        .init(id: 213,  name: "Netflix",          logoPath: "/wwemzKWzjKYJFfCeiB57q3r4Bcm.png",
              tmdbWatchProviderID: 8),
        .init(id: 1024, name: "Prime Video",      logoPath: "/ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png",
              jellyfinStudioNames: ["Prime Video", "Amazon Prime Video", "Amazon Studios"],
              tmdbWatchProviderID: 119),
        .init(id: 2739, name: "Disney+",          logoPath: "/gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png",
              jellyfinStudioNames: [
                  // Direct Disney+ tags (rare, but some scrapers stamp them)
                  "Disney+", "Disney Plus",
                  // Disney's film studios
                  "Walt Disney Pictures", "Walt Disney Studios",
                  "Walt Disney Animation Studios",
                  "Pixar", "Pixar Animation Studios",
                  "Marvel Studios", "Marvel Entertainment",
                  "Lucasfilm", "Lucasfilm Ltd.",
                  "Touchstone Pictures",
                  "Searchlight Pictures", "Fox Searchlight",
                  // 20th Century properties (acquired 2019, mostly Disney+ now)
                  "20th Century Studios", "20th Century Fox", "Twentieth Century Fox",
                  "20th Century Fox Television", "20th Television",
                  // Disney's TV networks + studios — covers most kids /
                  // family TV content (Bluey via "Ludo Studio", Modern
                  // Family via "20th Century Fox Television", etc.)
                  "Disney Channel", "Disney Junior", "Disney XD",
                  "Disney Television Animation", "Walt Disney Television",
                  "ABC Studios", "ABC Signature", "Touchstone Television",
                  "FX Productions", "FX Networks",
                  "National Geographic", "National Geographic Studios",
                  "Ludo Studio",
              ],
              tmdbWatchProviderID: 337),
        .init(id: 49,   name: "HBO",              logoPath: "/tuomPhY2UtuPTqqFnKMVHvSb724.png",
              jellyfinStudioNames: ["HBO", "HBO Max", "Max"],
              tmdbWatchProviderID: 1899),
        .init(id: 2552, name: "Apple TV+",        logoPath: "/4KAy34EHvRM25Ih8wb82AuGU7zJ.png",
              jellyfinStudioNames: ["Apple TV+", "Apple TV Plus", "Apple Studios"],
              tmdbWatchProviderID: 350),

        // MARK: - Tier 2 — second-tier global SVOD

        .init(id: 4330, name: "Paramount+",       logoPath: "/fi83B1oztoS47xxcemFdPMhIzK.png",
              jellyfinStudioNames: ["Paramount+", "Paramount Plus"],
              tmdbWatchProviderID: 531),
        .init(id: 3353, name: "Peacock",          logoPath: "/gIAcGTjKKr0KOHL5s4O36roJ8p7.png",
              tmdbWatchProviderID: 386),
        .init(id: 453,  name: "Hulu",             logoPath: "/pqUTCleNUiTLAVlelGxUgWn1ELh.png",
              tmdbWatchProviderID: 15),
        .init(id: 4353, name: "Discovery+",       logoPath: "/1D1bS3Dyw4ScYnFWTlBOvJXC3nb.png",
              jellyfinStudioNames: ["Discovery+", "Discovery Plus"],
              tmdbWatchProviderID: 524),

        // MARK: - Tier 3 — international / regional SVOD

        // Sky — DACH + UK premium. Studio aliases cover the various
        // Sky entities libraries actually tag (Sky Studios, Sky
        // Atlantic for the in-house drama label, etc.)
        .init(id: 5136, name: "Sky",              logoPath: "/1CN2IC17eLZZWV13X2rO4304dGG.png",
              jellyfinStudioNames: ["Sky", "Sky Studios", "Sky UK", "Sky Deutschland", "Sky Atlantic"],
              tmdbWatchProviderID: 29),
        // BBC iPlayer — the streaming app, distinct from the BBC One
        // broadcaster tile below. Catches UK shows whose Studios tag
        // is just "BBC" rather than the specific channel.
        .init(id: 1155, name: "BBC iPlayer",      logoPath: "/an0NpVNUK445AWDQTaLIFuL3isE.png",
              jellyfinStudioNames: ["BBC iPlayer", "BBC", "BBC Studios"],
              tmdbWatchProviderID: 38),
        // Canal+ — France premium
        .init(id: 285,  name: "Canal+",           logoPath: "/9aotxauvc9685tq9pTcRJszuT06.png",
              jellyfinStudioNames: ["Canal+", "Canal Plus"],
              tmdbWatchProviderID: 381),
        // Viaplay — Nordic default streamer (NO/SE/DK/FI)
        .init(id: 2869, name: "Viaplay",          logoPath: "/zs2yhnfMzRLoRtZgGRf41mqrLL0.png",
              tmdbWatchProviderID: 76),
        // Disney+ Hotstar — India (separate from global Disney+;
        // different content lineup and watch-provider entry).
        .init(id: 3919, name: "Hotstar",          logoPath: "/eBa3TplonEHlR6S2wjJ616KnwIh.png",
              jellyfinStudioNames: ["Hotstar", "Disney+ Hotstar", "Star India"],
              tmdbWatchProviderID: 122),
        // U-NEXT — Japan's largest non-anime streamer
        .init(id: 3869, name: "U-NEXT",           logoPath: "/4g6nXkkCQ31MrJG8Ud1fgxlQb36.png",
              tmdbWatchProviderID: 84),

        // MARK: - Tier 4 — niche / specialty SVOD

        // MUBI — global arthouse / cinephile streamer
        .init(id: 8303, name: "MUBI",             logoPath: "/ltHubSF7YTefDDE62BNlxROYnxc.png",
              tmdbWatchProviderID: 11),
        .init(id: 1112, name: "Crunchyroll",      logoPath: "/qqyXcZlJQKlRmAD1TCKV7mGLQlt.png",
              jellyfinStudioNames: ["Crunchyroll", "Funimation"],
              tmdbWatchProviderID: 283),

        // MARK: - Tier 5 — premium cable (no first-party watch-provider)

        .init(id: 67,   name: "Showtime",         logoPath: "/Allse9kbjiP6ExaQrnSpIhkurEi.png"),
        .init(id: 318,  name: "Starz",            logoPath: "/8GJjw3HHsAJYwIWKIPBPfqMxlEa.png"),
        .init(id: 359,  name: "Cinemax",          logoPath: "/6mSHSquNpfLgDdv6VnOOvC5Uz2h.png"),
        .init(id: 174,  name: "AMC",              logoPath: "/pmvRmATOCaDykE6JrVoeYxlFHw3.png",
              jellyfinStudioNames: ["AMC", "AMC+"]),

        // MARK: - Tier 6 — free AVOD

        // Tubi — global free AVOD (Fox-owned)
        .init(id: 5187, name: "Tubi",             logoPath: "/8OAFRLPQ4w888UDkDtnXpdnRfEQ.png",
              tmdbWatchProviderID: 73),
        // Pluto TV — global free AVOD (Paramount-owned)
        .init(id: 3245, name: "Pluto TV",         logoPath: "/6xI75dFULiEks0Dqm3Uag7CiC29.png",
              tmdbWatchProviderID: 300),

        // MARK: - Tier 7 — broadcast networks

        .init(id: 2,    name: "ABC",              logoPath: "/ndAvF4JLsliGreX87jAc9GdjmJY.png",
              jellyfinStudioNames: ["ABC", "ABC (US)"]),
        .init(id: 6,    name: "NBC",              logoPath: "/o3OedEP0f9mfZr33jz2BfXOUK5.png"),
        .init(id: 16,   name: "CBS",              logoPath: "/nm8d7P7MJNiBLdgIzUK0gkuEA4r.png"),
        .init(id: 19,   name: "FOX",              logoPath: "/1DSpHrWyOORkL9N2QHX7Adt31mQ.png",
              jellyfinStudioNames: ["FOX", "Fox"]),
        .init(id: 71,   name: "The CW",           logoPath: "/ge9hzeaU7nMtQ4PjkFlc68dGAJ9.png",
              jellyfinStudioNames: ["The CW", "The WB"]),
        .init(id: 4,    name: "BBC One",          logoPath: "/mVn7xESaTNmjBUyUtGNvDQd3CT1.png",
              jellyfinStudioNames: ["BBC One", "BBC", "BBC iPlayer", "BBC Studios"]),

        // MARK: - Tier 8 — kids / animation

        .init(id: 56,   name: "Cartoon Network",  logoPath: "/c5OC6oVCg6QP4eqzW6XIq17CQjI.png"),
        .init(id: 80,   name: "Adult Swim",       logoPath: "/9AKyspxVzywuaMuZ1Bvilu8sXly.png"),
        .init(id: 13,   name: "Nickelodeon",      logoPath: "/ikZXxg6GnwpzqiZbRPhJGaZapqB.png"),
    ]

    static let studios: [CatalogProvider] = [
        .init(id: 2,      name: "Disney",                 logoPath: "/wdrCwmRnLFJhEoH8GSfymY85KHT.png",
              jellyfinStudioNames: ["Disney", "Walt Disney Pictures", "Walt Disney Studios"]),
        .init(id: 127928, name: "20th Century Studios",   logoPath: "/h0rjX5vjW5r8yEnUBStFarjcLT4.png",
              jellyfinStudioNames: ["20th Century Studios", "20th Century Fox", "Twentieth Century Fox"]),
        .init(id: 34,     name: "Sony Pictures",          logoPath: "/GagSvqWlyPdkFHMfQ3pNq6ix9P.png",
              jellyfinStudioNames: ["Sony Pictures", "Sony Pictures Entertainment", "Columbia Pictures"]),
        .init(id: 174,    name: "Warner Bros. Pictures",  logoPath: "/ky0xOc5OrhzkZ1N6KyUxacfQsCk.png",
              jellyfinStudioNames: ["Warner Bros. Pictures", "Warner Bros.", "Warner Bros"]),
        .init(id: 33,     name: "Universal",              logoPath: "/8lvHyhjr8oUKOOy2dKXoALWKdp0.png",
              jellyfinStudioNames: ["Universal", "Universal Pictures"]),
        .init(id: 4,      name: "Paramount",              logoPath: "/fycMZt242LVjagMByZOLUGbCvv3.png",
              jellyfinStudioNames: ["Paramount", "Paramount Pictures"]),
        .init(id: 3,      name: "Pixar",                  logoPath: "/1TjvGVDMYsj6JBxOAkUHpPEwLf7.png",
              jellyfinStudioNames: ["Pixar", "Pixar Animation Studios"]),
        .init(id: 521,    name: "DreamWorks",             logoPath: "/kP7t6RwGz2AvvTkvnI1uteEwHet.png",
              jellyfinStudioNames: ["DreamWorks", "DreamWorks Pictures", "DreamWorks Animation"]),
        .init(id: 420,    name: "Marvel Studios",         logoPath: "/hUzeosd33nzE5MCNsZxCGEKTXaQ.png"),
        .init(id: 9993,   name: "DC",                     logoPath: "/2Tc1P3Ac8M479naPp1kYT3izLS5.png",
              jellyfinStudioNames: ["DC", "DC Comics", "DC Films", "DC Studios"]),
        .init(id: 41077,  name: "A24",                    logoPath: "/1ZXsGaFPgrgS6ZZGS37AqD5uU12.png"),
    ]
}
