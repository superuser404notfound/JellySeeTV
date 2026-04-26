import SwiftUI

struct FilteredGridView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var items: [JellyfinItem] = []
    @State private var isLoading = true
    @State private var isAugmenting = false
    @State private var selectedItem: JellyfinItem?
    @FocusState private var focusedItemID: String?
    @Environment(\.dismiss) private var dismiss

    let title: String
    let query: ItemQuery
    /// Optional TMDB watch-provider id. When set, after the studio
    /// filter resolves we ask Jellyseerr for the live "currently
    /// streaming on this service" list and look up any matches in
    /// the local library. Lets shows like Modern Family or Bluey
    /// surface under Disney+ even though their Studios tag points at
    /// 20th Century Fox Television / Ludo Studio respectively.
    var smartProviderID: Int? = nil
    var smartProviderRegion: String? = nil
    /// Stable identifier used by FilterCache to persist the final
    /// merged item list. Independent of `smartProviderID` so even
    /// providers without a watch-provider concept (broadcast nets
    /// like ABC / NBC / CBS) still get their result cached — and
    /// therefore become eligible for the empty-tile-hide pass on
    /// the next visit.
    var cacheKey: String? = nil

    var body: some View {
        ScrollView {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 20)

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    // Focusable element so Menu button works during loading
                    Button("") { dismiss() }
                        .opacity(0)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("home.retry")
                        .foregroundStyle(.secondary)
                    Button { dismiss() } label: {
                        Text("detail.showSeries")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 220), spacing: 40)
                ], spacing: 50) {
                    ForEach(items) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            MediaCard(
                                item: item,
                                imageURL: dependencies.jellyfinImageService.posterURL(for: item),
                                isFocused: focusedItemID == item.id
                            )
                        }
                        .buttonStyle(GridCardButtonStyle())
                        .focused($focusedItemID, equals: item.id)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedItem) { item in
            DetailRouterView(item: item)
        }
        .task {
            await loadItems()
            if let firstID = items.first?.id {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedItemID = firstID
                }
            }
        }
    }

    /// Phase-1 (studio match) results, kept separate from `items` so
    /// the augmentation refresh can rebuild the merged grid without
    /// re-running the studio query.
    @State private var studioItems: [JellyfinItem] = []

    private func loadItems() async {
        guard let userID = appState.activeUser?.id else { return }

        // Synchronous cache hit — display immediately, no spinner.
        // We cache the fully-resolved JellyfinItems so the second
        // tap onwards renders before any network roundtrip lands.
        if let key = cacheKey,
           let cached = FilterCache.shared.homeFilterItems(filterKey: key),
           !cached.isEmpty {
            items = cached
            isLoading = false
        } else {
            isLoading = true
        }

        async let studioMatchTask: [JellyfinItem] = {
            do {
                return try await dependencies.jellyfinLibraryService.getItems(
                    userID: userID, query: query
                ).items
            } catch {
                return []
            }
        }()

        async let allLibraryTask: [JellyfinItem] = {
            guard smartProviderID != nil else { return [] }
            // Fetch the entire library in one shot rather than running
            // per-id `AnyProviderIdEquals` lookups. Robust against
            // Jellyfin version quirks and amortises across every
            // TMDB id we want to resolve.
            let allQuery = ItemQuery(
                includeItemTypes: [.movie, .series],
                sortBy: "SortName",
                sortOrder: "Ascending",
                limit: 10000
            )
            return (try? await dependencies.jellyfinLibraryService.getItems(
                userID: userID, query: allQuery
            ).items) ?? []
        }()

        let phase1 = await studioMatchTask
        studioItems = phase1
        let allItems = await allLibraryTask

        // Build TMDB-id → JellyfinItem map once and reuse for the
        // background refresh.
        var tmdbMap: [Int: JellyfinItem] = [:]
        for item in allItems {
            if let id = item.tmdbID { tmdbMap[id] = item }
        }

        // No cache yet → at least surface the studio match while the
        // watch-provider phase runs.
        if items.isEmpty {
            items = phase1
            isLoading = false
        }

        // Always refresh — the cache is stale-while-revalidate. The
        // fresh list replaces whatever the cache held, so titles that
        // rotated off the service since last visit drop out.
        if let providerID = smartProviderID, let region = smartProviderRegion {
            await refreshWatchProviderAugment(
                providerID: providerID,
                region: region,
                tmdbMap: tmdbMap
            )
        } else {
            // No smart filter (broadcast networks, generic genre /
            // studio tiles) — Phase 1 is the final result. Persist
            // it so the empty-tile-hide pass on the next visit has
            // a count to work with, and so a re-tap renders without
            // the studio-query roundtrip.
            items = phase1
            if let key = cacheKey {
                FilterCache.shared.setHomeFilterItems(phase1, filterKey: key)
            }
        }
    }

    /// Merge studio-match (Phase 1) with watch-provider matches
    /// (Phase 2). Phase 1 keeps its server-side ordering at the top,
    /// Phase 2 extras are sorted alphabetically and appended.
    private func mergePhases(
        phase1: [JellyfinItem],
        phase2: [JellyfinItem]
    ) -> [JellyfinItem] {
        let phase1IDs = Set(phase1.map(\.id))
        let extras = phase2
            .filter { !phase1IDs.contains($0.id) }
            .sorted { $0.name < $1.name }
        return phase1 + extras
    }

    /// Background refresh of the TMDB watch-provider id list: 5
    /// pages each on movies + tv, then re-resolve against the local
    /// library map and write the fresh ids to the cache. Shows the
    /// updated grid the moment the new list lands. Stale entries
    /// drop out automatically because the merged grid is rebuilt
    /// from scratch every refresh.
    private func refreshWatchProviderAugment(
        providerID: Int,
        region: String,
        tmdbMap: [Int: JellyfinItem]
    ) async {
        isAugmenting = true
        defer { isAugmenting = false }

        let discoverService = dependencies.seerrDiscoverService
        var providerTmdbIDs: Set<Int> = []
        await withTaskGroup(of: Set<Int>.self) { group in
            for page in 1...5 {
                group.addTask {
                    let movies = (try? await discoverService.moviesByWatchProvider(
                        providerID: providerID, region: region, page: page
                    ))?.results.map(\.id) ?? []
                    let tv = (try? await discoverService.tvByWatchProvider(
                        providerID: providerID, region: region, page: page
                    ))?.results.map(\.id) ?? []
                    return Set(movies + tv)
                }
            }
            for await ids in group { providerTmdbIDs.formUnion(ids) }
        }

        FilterCache.shared.setSmartFilterIDs(
            Array(providerTmdbIDs), providerID: providerID, region: region
        )

        let phase2Items = providerTmdbIDs.compactMap { tmdbMap[$0] }
        let merged = mergePhases(phase1: studioItems, phase2: phase2Items)
        items = merged

        // Persist the fully-resolved list so the next visit can
        // hydrate the grid synchronously — no library fetch, no
        // watch-provider roundtrip needed for the initial display.
        if let key = cacheKey {
            FilterCache.shared.setHomeFilterItems(merged, filterKey: key)
        }
    }
}

struct GridCardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        // Stroke is drawn inside MediaCard (around the poster only),
        // keeping the title text below the card outside the outline.
        configuration.label
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 20, y: 10)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
