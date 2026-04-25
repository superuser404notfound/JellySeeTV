import Foundation

struct SeerrMovieDetail: Codable, Sendable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let runtime: Int?
    let voteAverage: Double?
    let genres: [SeerrGenre]?
    let mediaInfo: SeerrMediaInfo?

    var displayYear: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }
}

struct SeerrTVDetail: Codable, Sendable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genres: [SeerrGenre]?
    let numberOfSeasons: Int?
    let seasons: [SeerrSeason]?
    let mediaInfo: SeerrMediaInfo?

    var displayYear: String? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return String(firstAirDate.prefix(4))
    }
}

struct SeerrSeason: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let episodeCount: Int?
    let airDate: String?
    let posterPath: String?
}

struct SeerrGenre: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
}

/// Per-season detail returned from `/tv/{id}/season/{n}` — used to
/// render the read-only episode list inside CatalogDetailView. Note
/// that the request endpoint still only accepts whole seasons; this
/// payload is informational so the user can preview what they're
/// asking for before they hit Submit.
struct SeerrSeasonDetail: Codable, Sendable, Equatable {
    let id: Int
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let airDate: String?
    let episodes: [SeerrEpisode]?
}

struct SeerrEpisode: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let episodeNumber: Int
    let seasonNumber: Int?
    let name: String?
    let overview: String?
    let stillPath: String?
    let airDate: String?
    let voteAverage: Double?
    let runtime: Int?
}
