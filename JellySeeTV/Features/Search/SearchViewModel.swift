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

    /// Monotonic counter for in-flight searches. Each scheduled search
    /// captures its own ID; only the run whose ID still matches
    /// `currentSearchID` at write-time is allowed to publish results.
    /// Plain `Task.isCancelled` is not enough here: the inner network
    /// helpers swallow cancellation into `[]`, which would otherwise
    /// blow away a newer search's results with empty data.
    private var currentSearchID: UInt64 = 0

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
            // Bump the ID so any in-flight task is also disqualified
            // from writing — even the cleared state belongs to the
            // newest "search" (which is "no search").
            currentSearchID &+= 1
            jellyfinResults = []
            seerrResults = []
            isSearching = false
            errorMessage = nil
            return
        }

        currentSearchID &+= 1
        let id = currentSearchID

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            await self.runSearch(query: trimmed, id: id)
        }
    }

    private func runSearch(query: String, id: UInt64) async {
        isSearching = true
        errorMessage = nil

        async let jfTask = searchJellyfin(query: query)
        async let seerrTask = searchSeerr(query: query)

        let (jfItems, seerrItems) = await (jfTask, seerrTask)

        // Only publish if we are still the most recent search. A run
        // that's been superseded must not overwrite the newer query's
        // results — including not flipping isSearching back to false,
        // which would tell the UI "done" while a fresher run is still
        // mid-flight.
        guard id == currentSearchID else { return }

        jellyfinResults = jfItems
        seerrResults = deduplicate(seerr: seerrItems, against: jfItems)
        isSearching = false
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
