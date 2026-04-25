import SwiftUI

enum HomeRowType: String, Codable, Sendable, CaseIterable, Identifiable {
    // Declaration order is the default display order for new installs
    // (defaultConfig() uses allCases.enumerated() for sortOrder). Existing
    // users keep whatever order they saved; this only affects fresh
    // installs and a Reset-to-Default.
    case continueWatching
    case nextUp
    case favorites
    case latestMovies
    case latestShows
    case discoverProviders
    case genres
    case collections
    case recentlyAdded
    case topRatedMovies
    case topRatedShows
    case allMovies
    case allSeries

    var id: String { rawValue }

    var defaultEnabled: Bool {
        switch self {
        case .continueWatching, .nextUp, .favorites, .latestMovies,
             .latestShows, .discoverProviders, .genres:
            true
        default:
            false
        }
    }

    var cardStyle: MediaCardStyle {
        switch self {
        case .continueWatching, .nextUp:
            .landscape
        default:
            .poster
        }
    }

    var usesBackdrop: Bool {
        switch self {
        case .continueWatching, .nextUp:
            true
        default:
            false
        }
    }

    /// Genres show tag cards rather than media items.
    var isTagRow: Bool {
        switch self {
        case .genres:
            true
        default:
            false
        }
    }

    /// True for rows whose contents are *not* sourced from Jellyfin —
    /// today only the Discover (Jellyseerr) streaming-provider row,
    /// which renders a hardcoded provider list with TMDB logos and
    /// pushes a Jellyseerr-backed filter grid instead of the local
    /// FilteredGridView.
    var isDiscoverProviderRow: Bool { self == .discoverProviders }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .continueWatching: "home.continueWatching"
        case .nextUp: "home.nextUp"
        case .latestMovies: "home.latestMovies"
        case .latestShows: "home.latestShows"
        case .allMovies: "home.allMovies"
        case .allSeries: "home.allSeries"
        case .favorites: "home.favorites"
        case .topRatedMovies: "home.topRatedMovies"
        case .topRatedShows: "home.topRatedShows"
        case .recentlyAdded: "home.recentlyAdded"
        case .genres: "home.genres"
        case .collections: "home.collections"
        case .discoverProviders: "home.discoverProviders"
        }
    }

    var systemImage: String {
        switch self {
        case .continueWatching: "play.circle"
        case .nextUp: "forward"
        case .latestMovies: "film"
        case .latestShows: "tv"
        case .allMovies: "film.stack"
        case .allSeries: "rectangle.stack"
        case .favorites: "heart.fill"
        case .topRatedMovies: "star.fill"
        case .topRatedShows: "star.fill"
        case .recentlyAdded: "clock"
        case .genres: "tag"
        case .collections: "rectangle.stack.fill"
        case .discoverProviders: "tv.badge.wifi"
        }
    }
}

struct HomeRowConfig: Codable, Sendable, Identifiable, Equatable {
    let type: HomeRowType
    var isEnabled: Bool
    var sortOrder: Int

    var id: String { type.rawValue }

    static func defaultConfig() -> [HomeRowConfig] {
        HomeRowType.allCases.enumerated().map { index, type in
            HomeRowConfig(type: type, isEnabled: type.defaultEnabled, sortOrder: index)
        }
    }
}
