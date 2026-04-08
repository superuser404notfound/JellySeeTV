import SwiftUI

enum HomeRowType: String, Codable, Sendable, CaseIterable, Identifiable {
    case continueWatching
    case nextUp
    case latestMovies
    case latestShows
    case allMovies
    case allSeries
    case favorites
    case topRatedMovies
    case topRatedShows
    case recentlyAdded
    case genres
    case studios

    var id: String { rawValue }

    var defaultEnabled: Bool {
        switch self {
        case .continueWatching, .nextUp, .latestMovies, .latestShows, .favorites, .genres:
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

    /// Genres and Studios are special -- they show tag cards, not media items
    var isTagRow: Bool {
        switch self {
        case .genres, .studios:
            true
        default:
            false
        }
    }

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
        case .studios: "home.studios"
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
        case .studios: "building.2"
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
