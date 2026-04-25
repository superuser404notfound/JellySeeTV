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
