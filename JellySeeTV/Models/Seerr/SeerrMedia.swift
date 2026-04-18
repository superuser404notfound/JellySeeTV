import Foundation

struct SeerrMedia: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let mediaType: SeerrMediaType
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let mediaInfo: SeerrMediaInfo?

    var displayTitle: String {
        title ?? name ?? originalTitle ?? originalName ?? ""
    }

    var displayYear: String? {
        let raw = releaseDate ?? firstAirDate
        guard let raw, raw.count >= 4 else { return nil }
        return String(raw.prefix(4))
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(mediaType)
    }

    static func == (lhs: SeerrMedia, rhs: SeerrMedia) -> Bool {
        lhs.id == rhs.id && lhs.mediaType == rhs.mediaType
    }
}

struct SeerrMediaInfo: Codable, Sendable, Equatable {
    let id: Int?
    let tmdbId: Int?
    let status: SeerrMediaStatus?
    let requests: [SeerrRequest]?
}
