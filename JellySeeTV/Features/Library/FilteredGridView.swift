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

    private func loadItems() async {
        guard let userID = appState.activeUser?.id else { return }
        isLoading = true

        // Studio match (Phase 1) and the full-library fetch needed
        // for Phase 2 run in parallel — the user sees Phase 1 results
        // the moment they're back, Phase 2 can start matching as soon
        // as both responses are in.
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
            // per-id `AnyProviderIdEquals` lookups. The earlier
            // approach was fragile — Jellyfin's exact format / casing
            // for that filter varies enough between versions that
            // some users got zero matches even though the items were
            // sitting right there. Pulling everything once and doing
            // a hash lookup is robust and amortises across all the
            // TMDB ids we want to resolve.
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

        let studioItems = await studioMatchTask
        items = studioItems
        isLoading = false

        if let providerID = smartProviderID, let region = smartProviderRegion {
            let allItems = await allLibraryTask
            await augmentWithWatchProvider(
                providerID: providerID,
                region: region,
                allLibraryItems: allItems
            )
        }
    }

    /// Phase 2: pull the live "what's currently streaming on this
    /// service" list from Jellyseerr (5 pages of movies + 5 pages of
    /// tv) and match the TMDB ids against the local library. Anything
    /// not already in the studio result set is appended in alphabetic
    /// order so the augmented tail stays consistent with Phase 1.
    private func augmentWithWatchProvider(
        providerID: Int,
        region: String,
        allLibraryItems: [JellyfinItem]
    ) async {
        isAugmenting = true
        defer { isAugmenting = false }

        // Build TMDB-id → JellyfinItem map once; the lookup is then
        // O(1) per matching watch-provider id. Items without a TMDB
        // id (no scraper match, manual import without metadata) are
        // simply unreachable through this path — they still surface
        // via the studio filter.
        var tmdbMap: [Int: JellyfinItem] = [:]
        for item in allLibraryItems {
            if let id = item.tmdbID {
                tmdbMap[id] = item
            }
        }
        guard !tmdbMap.isEmpty else { return }

        // Pull the live watch-provider list from Jellyseerr. 5 pages
        // each on movies + tv ≈ 200 ids — covers anything mainstream
        // enough to be in a typical home library.
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

        // Translate matching TMDB ids back to Jellyfin items, drop
        // anything Phase 1 already showed, sort the additions
        // alphabetically.
        let existingItemIDs = Set(items.map(\.id))
        let additions = providerTmdbIDs
            .compactMap { tmdbMap[$0] }
            .filter { !existingItemIDs.contains($0.id) }
            .sorted { $0.name < $1.name }

        guard !additions.isEmpty else { return }
        items.append(contentsOf: additions)
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
