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

    /// Cross-type stable identifier for dedup + ForEach `.id`. Two
    /// items can share the same numeric `id` across movie / tv (TMDB
    /// reuses ids per type), so the media type prefix is required.
    var stableKey: String { "\(mediaType.rawValue)-\(id)" }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(mediaType)
    }

    static func == (lhs: SeerrMedia, rhs: SeerrMedia) -> Bool {
        lhs.id == rhs.id && lhs.mediaType == rhs.mediaType
    }

    /// Minimal stub used when we navigate to `CatalogDetailView` from a
    /// context where we only have the TMDB id (e.g. the "Request in
    /// Seerr" button on a Jellyfin detail view). `CatalogDetailView`
    /// issues `/movie/{id}` or `/tv/{id}` in `load()` and fills in the
    /// rest, so stub fields are fine.
    static func stub(tmdbID: Int, mediaType: SeerrMediaType) -> SeerrMedia {
        SeerrMedia(
            id: tmdbID,
            mediaType: mediaType,
            title: nil, name: nil,
            originalTitle: nil, originalName: nil,
            overview: nil,
            posterPath: nil, backdropPath: nil,
            releaseDate: nil, firstAirDate: nil,
            voteAverage: nil,
            mediaInfo: nil
        )
    }
}

struct SeerrMediaInfo: Codable, Sendable, Equatable {
    let id: Int?
    let tmdbId: Int?
    let status: SeerrMediaStatus?
    let requests: [SeerrRequest]?
    /// Sonarr-scan derived per-season status. Authoritative for "is
    /// season N currently on the server?" — independent of whether a
    /// request entry still exists. A season the user added by hand
    /// (no request, manual Sonarr import) shows up here as
    /// `.available`, which the season tab needs to render its
    /// checkmark even when there's nothing in `requests` referencing
    /// it. A season whose files were deleted reverts to `.unknown`.
    let seasons: [SeerrMediaSeason]?
}

struct SeerrMediaSeason: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let seasonNumber: Int
    let status: SeerrMediaStatus?
    let status4k: SeerrMediaStatus?
}
