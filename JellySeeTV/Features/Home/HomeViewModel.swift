import SwiftUI

@Observable
final class HomeViewModel {
    var rows: [HomeRowData] = []
    var isLoading = true
    var errorMessage: String?
    var rowConfigs: [HomeRowConfig] = []

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
        self.rowConfigs = Self.loadRowConfigs()
    }

    func loadContent() async {
        isLoading = true
        errorMessage = nil

        do {
            libraries = try await libraryService.getLibraries(userID: userID)

            let enabledRows = rowConfigs
                .filter(\.isEnabled)
                .sorted { $0.sortOrder < $1.sortOrder }

            var loadedRows: [HomeRowData] = []

            for config in enabledRows {
                if let rowData = await loadRow(type: config.type) {
                    if !rowData.items.isEmpty {
                        loadedRows.append(rowData)
                    }
                }
            }

            rows = loadedRows
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
                let movieLibID = libraries.first { $0.libraryType == .movies }?.id
                items = try await libraryService.getLatestMedia(userID: userID, parentID: movieLibID, limit: 16)

            case .latestShows:
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
                    includeItemTypes: [.movie, .series],
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

            case .genres:
                // Genres row is special - handled differently in the UI
                return nil
            }

            return HomeRowData(type: type, items: items)
        } catch {
            return nil
        }
    }

    func imageURL(for item: JellyfinItem, rowType: HomeRowType) -> URL? {
        if rowType.usesBackdrop {
            return imageService.backdropURL(for: item) ?? imageService.posterURL(for: item)
        }
        return imageService.posterURL(for: item)
    }

    // MARK: - Config Persistence

    func updateRowConfig(_ configs: [HomeRowConfig]) {
        rowConfigs = configs
        Self.saveRowConfigs(configs)
    }

    func moveRow(from source: IndexSet, to destination: Int) {
        var enabled = rowConfigs.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
        enabled.move(fromOffsets: source, toOffset: destination)
        for (index, _) in enabled.enumerated() {
            if let configIndex = rowConfigs.firstIndex(where: { $0.type == enabled[index].type }) {
                rowConfigs[configIndex].sortOrder = index
            }
        }
        Self.saveRowConfigs(rowConfigs)
    }

    func toggleRow(_ type: HomeRowType) {
        if let index = rowConfigs.firstIndex(where: { $0.type == type }) {
            rowConfigs[index].isEnabled.toggle()
            Self.saveRowConfigs(rowConfigs)
        }
    }

    private static func loadRowConfigs() -> [HomeRowConfig] {
        guard let data = UserDefaults.standard.data(forKey: "homeRowConfigs"),
              let configs = try? JSONDecoder().decode([HomeRowConfig].self, from: data)
        else {
            return HomeRowConfig.defaultConfig()
        }
        // Add any new row types that didn't exist when the config was saved
        var result = configs
        for type in HomeRowType.allCases where !result.contains(where: { $0.type == type }) {
            result.append(HomeRowConfig(type: type, isEnabled: type.defaultEnabled, sortOrder: result.count))
        }
        return result
    }

    private static func saveRowConfigs(_ configs: [HomeRowConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: "homeRowConfigs")
        }
    }
}

struct HomeRowData: Identifiable, Sendable {
    let type: HomeRowType
    let items: [JellyfinItem]

    var id: String { type.rawValue }
}
