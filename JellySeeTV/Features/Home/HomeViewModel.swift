import SwiftUI

@Observable
final class HomeViewModel {
    var rows: [HomeRowData] = []
    var tagRows: [HomeTagRowData] = []
    var isLoading = true
    var errorMessage: String?
    var rowConfigs: [HomeRowConfig] = []
    var needsReload = false
    var reloadID = UUID()

    private let libraryService: JellyfinLibraryServiceProtocol
    private let imageService: JellyfinImageService
    private let userID: String
    private var libraries: [JellyfinLibrary] = []

    init(
        libraryService: JellyfinLibraryServiceProtocol,
        imageService: JellyfinImageService,
        userID: String
    ) {
        self.libraryService = libraryService
        self.imageService = imageService
        self.userID = userID
        self.rowConfigs = HomeRowConfig.loadFromStorage()
    }

    func loadContent() async {
        let isFirstLoad = rows.isEmpty && tagRows.isEmpty
        if isFirstLoad {
            isLoading = true
        }
        errorMessage = nil

        do {
            libraries = try await libraryService.getLibraries(userID: userID)

            let enabledRows = rowConfigs
                .filter(\.isEnabled)
                .sorted { $0.sortOrder < $1.sortOrder }

            var newRows: [HomeRowData] = []
            var newTagRows: [HomeTagRowData] = []

            for config in enabledRows {
                if config.type.isTagRow {
                    if let tagRow = await loadTagRow(type: config.type) {
                        if !tagRow.tags.isEmpty {
                            newTagRows.append(tagRow)
                        }
                    }
                } else {
                    if let rowData = await loadRow(type: config.type) {
                        if !rowData.items.isEmpty {
                            newRows.append(rowData)
                        }
                    }
                }
            }

            // Atomic swap -- old images stay visible until new data is ready
            rows = newRows
            tagRows = newTagRows
            reloadID = UUID()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadRow(type: HomeRowType) async -> HomeRowData? {
        do {
            let items: [JellyfinItem]

            switch type {
            case .continueWatching:
                let response = try await libraryService.getResumeItems(userID: userID, mediaType: "Video", limit: 16)
                items = response.items

            case .nextUp:
                let response = try await libraryService.getNextUp(userID: userID, seriesID: nil, limit: 16)
                items = response.items

            case .latestMovies:
                // Use /Items (not /Items/Latest) so BoxSet members don't
                // collapse into a single representative — Jellyfin's
                // Latest endpoint folds franchise movies (John Wick 1-4)
                // into one card even with GroupItems=false. DateCreated
                // desc gives us the same "newly added" semantics without
                // the grouping surprise.
                let movieLibID = libraries.first { $0.libraryType == .movies }?.id
                let query = ItemQuery(
                    parentID: movieLibID,
                    includeItemTypes: [.movie],
                    sortBy: "DateCreated",
                    sortOrder: "Descending",
                    limit: 16
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .latestShows:
                // Shows stay on /Items/Latest: its built-in grouping is
                // what we *want* here — show the series when a new
                // episode lands, not the raw episode with its own title
                // and screenshot. Using a DateCreated query here would
                // surface individual episodes instead of series.
                let showLibID = libraries.first { $0.libraryType == .tvshows }?.id
                items = try await libraryService.getLatestMedia(userID: userID, parentID: showLibID, limit: 16)

            case .allMovies:
                let query = ItemQuery(
                    includeItemTypes: [.movie],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 30
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .allSeries:
                let query = ItemQuery(
                    includeItemTypes: [.series],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 30
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .favorites:
                let query = ItemQuery(
                    includeItemTypes: [.movie, .series, .boxSet],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 30,
                    isFavorite: true
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .topRatedMovies:
                let query = ItemQuery(
                    includeItemTypes: [.movie],
                    sortBy: "CommunityRating",
                    sortOrder: "Descending",
                    limit: 20
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .topRatedShows:
                let query = ItemQuery(
                    includeItemTypes: [.series],
                    sortBy: "CommunityRating",
                    sortOrder: "Descending",
                    limit: 20
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .recentlyAdded:
                let query = ItemQuery(
                    includeItemTypes: [.movie, .series],
                    sortBy: "DateCreated",
                    sortOrder: "Descending",
                    limit: 20
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .collections:
                let query = ItemQuery(
                    includeItemTypes: [.boxSet],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 30
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .genres, .studios:
                return nil
            }

            return HomeRowData(type: type, items: items)
        } catch {
            return nil
        }
    }

    private func loadTagRow(type: HomeRowType) async -> HomeTagRowData? {
        do {
            let tags: [NamedItem]
            let isStudio = type == .studios

            switch type {
            case .genres:
                let allGenres = try await libraryService.getGenres(userID: userID)
                tags = allGenres.filter { GenreFilter.isPrimary($0.name) }
            case .studios:
                let allStudios = try await libraryService.getStudios(userID: userID)
                tags = allStudios.filter { StreamingProviders.isProvider($0.name) }
            default:
                return nil
            }

            // Fetch one item per tag in parallel for matching backdrops
            let tagItems: [(String, JellyfinItem?)] = await withTaskGroup(
                of: (String, JellyfinItem?).self,
                returning: [(String, JellyfinItem?)].self
            ) { group in
                for tag in tags {
                    group.addTask {
                        let query = ItemQuery(
                            includeItemTypes: [.movie, .series],
                            sortBy: "Random",
                            limit: 1,
                            genres: isStudio ? nil : [tag.name],
                            studioNames: isStudio ? [tag.name] : nil
                        )
                        let item = try? await self.libraryService.getItems(userID: self.userID, query: query).items.first
                        return (tag.id, item)
                    }
                }
                var results: [(String, JellyfinItem?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            // Build cards on MainActor (image URL construction needs it)
            let itemMap = Dictionary(uniqueKeysWithValues: tagItems)
            let cardData: [TagCardData] = tags.map { tag in
                let item = itemMap[tag.id].flatMap { $0 }
                let backdropURL = item.flatMap { imageService.backdropURL(for: $0) ?? imageService.posterURL(for: $0) }
                let logoURL = isStudio ? imageService.studioLogoURL(studioName: tag.name) : nil
                return TagCardData(
                    id: tag.id,
                    name: tag.name,
                    backdropURL: backdropURL,
                    logoURL: logoURL,
                    isStudio: isStudio
                )
            }

            return HomeTagRowData(type: type, tags: cardData)
        } catch {
            return nil
        }
    }

    func imageURL(for item: JellyfinItem, rowType: HomeRowType) -> URL? {
        if rowType.usesBackdrop {
            // For continue watching / next up: use episode thumbnail first
            if item.type == .episode {
                return imageService.episodeThumbnailURL(for: item)
            }
            return imageService.backdropURL(for: item) ?? imageService.posterURL(for: item)
        }
        return imageService.posterURL(for: item)
    }

    func reloadConfig() {
        rowConfigs = HomeRowConfig.loadFromStorage()
    }

    /// Returns the ordered list of all sections (media rows + tag rows) in config order
    func orderedSections() -> [HomeSection] {
        let enabledConfigs = rowConfigs
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }

        return enabledConfigs.compactMap { config in
            if config.type.isTagRow {
                if let tagRow = tagRows.first(where: { $0.type == config.type }) {
                    return .tags(tagRow)
                }
            } else {
                if let row = rows.first(where: { $0.type == config.type }) {
                    return .media(row)
                }
            }
            return nil
        }
    }
}

enum HomeSection: Identifiable {
    case media(HomeRowData)
    case tags(HomeTagRowData)

    var id: String {
        switch self {
        case .media(let data): data.id
        case .tags(let data): data.id
        }
    }
}

struct HomeRowData: Identifiable, Sendable {
    let type: HomeRowType
    let items: [JellyfinItem]

    var id: String { type.rawValue }
}

struct HomeTagRowData: Identifiable, Sendable {
    let type: HomeRowType
    let tags: [TagCardData]

    var id: String { type.rawValue }
}
