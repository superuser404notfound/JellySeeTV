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
    /// TMDB-sourced related videos (trailers, teasers, clips).
    /// Jellyseerr proxies this through as a flat array on its
    /// /movie/{id} + /tv/{id} responses.
    let relatedVideos: [SeerrVideo]?

    var displayYear: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, originalTitle, overview, posterPath, backdropPath,
             releaseDate, runtime, voteAverage, genres, mediaInfo
        case relatedVideos = "relatedVideos"
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
    let relatedVideos: [SeerrVideo]?

    var displayYear: String? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return String(firstAirDate.prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, originalName, overview, posterPath, backdropPath,
             firstAirDate, voteAverage, genres, numberOfSeasons, seasons,
             mediaInfo
        case relatedVideos = "relatedVideos"
    }
}

/// A TMDB-sourced video attached to a movie or series. `site` is
/// usually "YouTube" (TrailerService only routes those). `key` is
/// the platform-specific video identifier — `https://youtu.be/<key>`
/// for YouTube.
struct SeerrVideo: Codable, Sendable, Equatable, Hashable, Identifiable {
    let key: String
    let name: String?
    let site: String?
    let type: String?
    let size: Int?
    let url: String?

    var id: String { key }

    /// "Trailer" is the TMDB type for the primary marketing trailer.
    /// Others are "Teaser", "Clip", "Featurette", "Behind the Scenes"…
    var isTrailer: Bool { type?.caseInsensitiveCompare("Trailer") == .orderedSame }
    var isYouTube: Bool { site?.caseInsensitiveCompare("YouTube") == .orderedSame }
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
