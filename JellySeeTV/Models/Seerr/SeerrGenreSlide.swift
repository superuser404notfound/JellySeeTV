import Foundation

/// One entry from `/api/v1/discover/genreslider/movie` (or `/tv`).
/// Jellyseerr returns the curated, populated genres for the
/// discover page along with a few backdrops we can use to render
/// genre cards with imagery instead of plain capsules.
struct SeerrGenreSlide: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let backdrops: [String]?

    /// Pick the first available backdrop. Used as a hero image on
    /// the genre tile; nil callers fall back to a solid-tint card.
    var primaryBackdrop: String? { backdrops?.first }
}
