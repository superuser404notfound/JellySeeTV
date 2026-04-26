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
        do {
            let response = try await dependencies.jellyfinLibraryService.getItems(
                userID: userID,
                query: query
            )
            items = response.items
        } catch {
            // Show empty state
        }
        isLoading = false

        // Phase 2: augment with TMDB watch-provider matches. Runs
        // after the studio filter has rendered so the user sees
        // immediate results; new items stream in as the lookup
        // completes.
        if let providerID = smartProviderID,
           let region = smartProviderRegion {
            await augmentWithWatchProvider(
                providerID: providerID,
                region: region,
                userID: userID
            )
        }
    }

    /// Pulls the live watch-provider list from Jellyseerr (`/discover/
    /// movies?watchProviders=…&watchRegion=…` plus the matching tv
    /// endpoint) and looks up any TMDB ids in the local Jellyfin
    /// library that the studio filter didn't already catch. Every
    /// per-id Jellyfin lookup is `AnyProviderIdEquals=tmdb.<id>`,
    /// throttled at 8 in flight so a moderately-sized library still
    /// feels snappy and a slow remote Jellyfin doesn't timeout.
    private func augmentWithWatchProvider(
        providerID: Int,
        region: String,
        userID: String
    ) async {
        isAugmenting = true
        defer { isAugmenting = false }

        // 1. TMDB ids already covered by the studio match
        let existingTmdbIDs: Set<Int> = Set(items.compactMap(\.tmdbID))

        // 2. Pull the live list from Jellyseerr — first 5 pages of
        //    movies + tv each (≤200 ids total). Higher than that
        //    starts hitting the long-tail of "technically streamable"
        //    titles the user almost certainly doesn't own.
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

        // 3. Subtract anything we already have so we don't refetch.
        let toLookup = Array(providerTmdbIDs.subtracting(existingTmdbIDs))
        guard !toLookup.isEmpty else { return }

        // 4. Per-id Jellyfin lookup with concurrency 8.
        let libraryService = dependencies.jellyfinLibraryService
        let augmentItems: [JellyfinItem] = await withTaskGroup(
            of: JellyfinItem?.self,
            returning: [JellyfinItem].self
        ) { group in
            let maxInFlight = 8
            var iter = toLookup.makeIterator()
            // Bootstrap initial batch
            for _ in 0..<maxInFlight {
                guard let id = iter.next() else { break }
                group.addTask {
                    let q = ItemQuery(
                        includeItemTypes: [.movie, .series],
                        limit: 1,
                        anyProviderIdEquals: "tmdb.\(id)"
                    )
                    return try? await libraryService.getItems(userID: userID, query: q).items.first
                }
            }
            var collected: [JellyfinItem] = []
            while let result = await group.next() {
                if let item = result { collected.append(item) }
                if let next = iter.next() {
                    group.addTask {
                        let q = ItemQuery(
                            includeItemTypes: [.movie, .series],
                            limit: 1,
                            anyProviderIdEquals: "tmdb.\(next)"
                        )
                        return try? await libraryService.getItems(userID: userID, query: q).items.first
                    }
                }
            }
            return collected
        }

        // 5. Merge — dedupe by Jellyfin item id (the source of
        //    truth — the same TMDB id can technically map to two
        //    library entries if the user has dupes).
        let existingIDs = Set(items.map(\.id))
        let additions = augmentItems.filter { !existingIDs.contains($0.id) }
        guard !additions.isEmpty else { return }
        // Append in alphabetical order so the augmented tail is
        // consistent with the studio-match head.
        items.append(contentsOf: additions.sorted { ($0.name) < ($1.name) })
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
