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
}

enum CatalogProviders {
    static let networks: [CatalogProvider] = [
        .init(id: 213,  name: "Netflix",          logoPath: "/wwemzKWzjKYJFfCeiB57q3r4Bcm.png"),
        .init(id: 2739, name: "Disney+",          logoPath: "/gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png"),
        .init(id: 1024, name: "Prime Video",      logoPath: "/ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png"),
        .init(id: 2552, name: "Apple TV+",        logoPath: "/4KAy34EHvRM25Ih8wb82AuGU7zJ.png"),
        .init(id: 453,  name: "Hulu",             logoPath: "/pqUTCleNUiTLAVlelGxUgWn1ELh.png"),
        .init(id: 49,   name: "HBO",              logoPath: "/tuomPhY2UtuPTqqFnKMVHvSb724.png"),
        .init(id: 4353, name: "Discovery+",       logoPath: "/1D1bS3Dyw4ScYnFWTlBOvJXC3nb.png"),
        .init(id: 2,    name: "ABC",              logoPath: "/ndAvF4JLsliGreX87jAc9GdjmJY.png"),
        .init(id: 19,   name: "FOX",              logoPath: "/1DSpHrWyOORkL9N2QHX7Adt31mQ.png"),
        .init(id: 359,  name: "Cinemax",          logoPath: "/6mSHSquNpfLgDdv6VnOOvC5Uz2h.png"),
        .init(id: 174,  name: "AMC",              logoPath: "/pmvRmATOCaDykE6JrVoeYxlFHw3.png"),
        .init(id: 67,   name: "Showtime",         logoPath: "/Allse9kbjiP6ExaQrnSpIhkurEi.png"),
        .init(id: 318,  name: "Starz",            logoPath: "/8GJjw3HHsAJYwIWKIPBPfqMxlEa.png"),
        .init(id: 71,   name: "The CW",           logoPath: "/ge9hzeaU7nMtQ4PjkFlc68dGAJ9.png"),
        .init(id: 6,    name: "NBC",              logoPath: "/o3OedEP0f9mfZr33jz2BfXOUK5.png"),
        .init(id: 16,   name: "CBS",              logoPath: "/nm8d7P7MJNiBLdgIzUK0gkuEA4r.png"),
        .init(id: 4330, name: "Paramount+",       logoPath: "/fi83B1oztoS47xxcemFdPMhIzK.png"),
        .init(id: 4,    name: "BBC One",          logoPath: "/mVn7xESaTNmjBUyUtGNvDQd3CT1.png"),
        .init(id: 56,   name: "Cartoon Network",  logoPath: "/c5OC6oVCg6QP4eqzW6XIq17CQjI.png"),
        .init(id: 80,   name: "Adult Swim",       logoPath: "/9AKyspxVzywuaMuZ1Bvilu8sXly.png"),
        .init(id: 13,   name: "Nickelodeon",      logoPath: "/ikZXxg6GnwpzqiZbRPhJGaZapqB.png"),
        .init(id: 3353, name: "Peacock",          logoPath: "/gIAcGTjKKr0KOHL5s4O36roJ8p7.png"),
    ]

    static let studios: [CatalogProvider] = [
        .init(id: 2,      name: "Disney",                 logoPath: "/wdrCwmRnLFJhEoH8GSfymY85KHT.png"),
        .init(id: 127928, name: "20th Century Studios",   logoPath: "/h0rjX5vjW5r8yEnUBStFarjcLT4.png"),
        .init(id: 34,     name: "Sony Pictures",          logoPath: "/GagSvqWlyPdkFHMfQ3pNq6ix9P.png"),
        .init(id: 174,    name: "Warner Bros. Pictures",  logoPath: "/ky0xOc5OrhzkZ1N6KyUxacfQsCk.png"),
        .init(id: 33,     name: "Universal",              logoPath: "/8lvHyhjr8oUKOOy2dKXoALWKdp0.png"),
        .init(id: 4,      name: "Paramount",              logoPath: "/fycMZt242LVjagMByZOLUGbCvv3.png"),
        .init(id: 3,      name: "Pixar",                  logoPath: "/1TjvGVDMYsj6JBxOAkUHpPEwLf7.png"),
        .init(id: 521,    name: "DreamWorks",             logoPath: "/kP7t6RwGz2AvvTkvnI1uteEwHet.png"),
        .init(id: 420,    name: "Marvel Studios",         logoPath: "/hUzeosd33nzE5MCNsZxCGEKTXaQ.png"),
        .init(id: 9993,   name: "DC",                     logoPath: "/2Tc1P3Ac8M479naPp1kYT3izLS5.png"),
        .init(id: 41077,  name: "A24",                    logoPath: "/1ZXsGaFPgrgS6ZZGS37AqD5uU12.png"),
    ]
}
