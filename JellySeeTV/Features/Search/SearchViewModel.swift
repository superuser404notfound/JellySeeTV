import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var query: String = ""
    var jellyfinResults: [JellyfinItem] = []
    var seerrResults: [SeerrMedia] = []
    var isSearching = false
    var errorMessage: String?

    private let itemService: JellyfinItemServiceProtocol
    private let seerrSearchService: SeerrSearchServiceProtocol?
    private let userID: String
    private var searchTask: Task<Void, Never>?

    init(
        itemService: JellyfinItemServiceProtocol,
        seerrSearchService: SeerrSearchServiceProtocol?,
        userID: String
    ) {
        self.itemService = itemService
        self.seerrSearchService = seerrSearchService
        self.userID = userID
    }

    /// Debounced search. Cancels the previous task so fast typing only
    /// runs the final query against the servers (saves bandwidth and
    /// stops results arriving out-of-order).
    func scheduleSearch() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            jellyfinResults = []
            seerrResults = []
            isSearching = false
            errorMessage = nil
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            await self.runSearch(query: trimmed)
        }
    }

    private func runSearch(query: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        async let jfTask = searchJellyfin(query: query)
        async let seerrTask = searchSeerr(query: query)

        let (jfItems, seerrItems) = await (jfTask, seerrTask)
        guard !Task.isCancelled else { return }

        jellyfinResults = jfItems
        seerrResults = deduplicate(seerr: seerrItems, against: jfItems)
    }

    private func searchJellyfin(query: String) async -> [JellyfinItem] {
        let q = ItemQuery(
            includeItemTypes: [.movie, .series],
            sortBy: "SortName",
            sortOrder: "Ascending",
            limit: 30,
            searchTerm: query
        )
        do {
            let resp = try await itemService.getCollectionItems(userID: userID, query: q)
            return resp.items
        } catch {
            return []
        }
    }

    private func searchSeerr(query: String) async -> [SeerrMedia] {
        guard let service = seerrSearchService else { return [] }
        do {
            let result = try await service.search(query: query, page: 1)
            return result.results
        } catch {
            return []
        }
    }

    /// Remove Seerr results that already exist in the Jellyfin library.
    /// Primary signal: TMDB id. Fallback when Jellyfin has no TMDB
    /// provider id (manual imports, old scanner versions): normalized
    /// title + production year.
    private func deduplicate(seerr: [SeerrMedia], against jellyfin: [JellyfinItem]) -> [SeerrMedia] {
        let jellyfinTmdbIDs = Set(jellyfin.compactMap { $0.tmdbID })
        let jellyfinTitleYears = Set(jellyfin.map { titleYearKey(name: $0.name, year: $0.productionYear) })

        return seerr.filter { media in
            if jellyfinTmdbIDs.contains(media.id) { return false }
            let mediaYear = Int(media.displayYear ?? "")
            let key = titleYearKey(name: media.displayTitle, year: mediaYear)
            return !jellyfinTitleYears.contains(key)
        }
    }

    private func titleYearKey(name: String, year: Int?) -> String {
        let normalized = name
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        return "\(normalized)|\(year ?? 0)"
    }
}
