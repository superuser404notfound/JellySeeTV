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

    init(id: Int, name: String, logoPath: String, jellyfinStudioNames: [String]? = nil) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
        self.jellyfinStudioNames = jellyfinStudioNames ?? [name]
    }
}

enum CatalogProviders {
    static let networks: [CatalogProvider] = [
        .init(id: 213,  name: "Netflix",          logoPath: "/wwemzKWzjKYJFfCeiB57q3r4Bcm.png"),
        .init(id: 2739, name: "Disney+",          logoPath: "/gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png",
              jellyfinStudioNames: ["Disney+", "Disney Plus", "Walt Disney Pictures", "Walt Disney Studios"]),
        .init(id: 1024, name: "Prime Video",      logoPath: "/ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png",
              jellyfinStudioNames: ["Prime Video", "Amazon Prime Video", "Amazon Studios"]),
        .init(id: 2552, name: "Apple TV+",        logoPath: "/4KAy34EHvRM25Ih8wb82AuGU7zJ.png",
              jellyfinStudioNames: ["Apple TV+", "Apple TV Plus", "Apple Studios"]),
        .init(id: 453,  name: "Hulu",             logoPath: "/pqUTCleNUiTLAVlelGxUgWn1ELh.png"),
        .init(id: 49,   name: "HBO",              logoPath: "/tuomPhY2UtuPTqqFnKMVHvSb724.png",
              jellyfinStudioNames: ["HBO", "HBO Max", "Max"]),
        .init(id: 4353, name: "Discovery+",       logoPath: "/1D1bS3Dyw4ScYnFWTlBOvJXC3nb.png",
              jellyfinStudioNames: ["Discovery+", "Discovery Plus"]),
        .init(id: 2,    name: "ABC",              logoPath: "/ndAvF4JLsliGreX87jAc9GdjmJY.png",
              jellyfinStudioNames: ["ABC", "ABC (US)"]),
        .init(id: 19,   name: "FOX",              logoPath: "/1DSpHrWyOORkL9N2QHX7Adt31mQ.png",
              jellyfinStudioNames: ["FOX", "Fox"]),
        .init(id: 359,  name: "Cinemax",          logoPath: "/6mSHSquNpfLgDdv6VnOOvC5Uz2h.png"),
        .init(id: 174,  name: "AMC",              logoPath: "/pmvRmATOCaDykE6JrVoeYxlFHw3.png",
              jellyfinStudioNames: ["AMC", "AMC+"]),
        .init(id: 67,   name: "Showtime",         logoPath: "/Allse9kbjiP6ExaQrnSpIhkurEi.png"),
        .init(id: 318,  name: "Starz",            logoPath: "/8GJjw3HHsAJYwIWKIPBPfqMxlEa.png"),
        .init(id: 71,   name: "The CW",           logoPath: "/ge9hzeaU7nMtQ4PjkFlc68dGAJ9.png",
              jellyfinStudioNames: ["The CW", "The WB"]),
        .init(id: 6,    name: "NBC",              logoPath: "/o3OedEP0f9mfZr33jz2BfXOUK5.png"),
        .init(id: 16,   name: "CBS",              logoPath: "/nm8d7P7MJNiBLdgIzUK0gkuEA4r.png"),
        .init(id: 4330, name: "Paramount+",       logoPath: "/fi83B1oztoS47xxcemFdPMhIzK.png",
              jellyfinStudioNames: ["Paramount+", "Paramount Plus"]),
        .init(id: 4,    name: "BBC One",          logoPath: "/mVn7xESaTNmjBUyUtGNvDQd3CT1.png",
              jellyfinStudioNames: ["BBC One", "BBC", "BBC iPlayer", "BBC Studios"]),
        .init(id: 56,   name: "Cartoon Network",  logoPath: "/c5OC6oVCg6QP4eqzW6XIq17CQjI.png"),
        .init(id: 80,   name: "Adult Swim",       logoPath: "/9AKyspxVzywuaMuZ1Bvilu8sXly.png"),
        .init(id: 13,   name: "Nickelodeon",      logoPath: "/ikZXxg6GnwpzqiZbRPhJGaZapqB.png"),
        .init(id: 3353, name: "Peacock",          logoPath: "/gIAcGTjKKr0KOHL5s4O36roJ8p7.png"),
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
