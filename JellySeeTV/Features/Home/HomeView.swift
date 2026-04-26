import SwiftUI

struct HomeView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: HomeViewModel?
    @State private var selectedItem: JellyfinItem?
    @State private var selectedFilter: FilterDestination?

    /// How long the home feed is considered fresh before a revisit
    /// triggers an automatic reload.
    private static let refreshStaleSeconds: TimeInterval = 60

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = vm.errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text(error)
                                .foregroundStyle(.secondary)
                            Button("home.retry") {
                                Task { await vm.loadContent() }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        contentView(vm: vm)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                DetailRouterView(item: item)
            }
            .navigationDestination(item: $selectedFilter) { filter in
                FilteredGridView(
                    title: filter.title,
                    query: filter.query,
                    smartProviderID: filter.smartProviderID,
                    smartProviderRegion: filter.smartProviderRegion,
                    cacheKey: filter.cacheKey
                )
            }
        }
        .onAppear {
            guard let userID = appState.activeUser?.id else { return }
            if viewModel == nil {
                viewModel = HomeViewModel(
                    libraryService: dependencies.jellyfinLibraryService,
                    imageService: dependencies.jellyfinImageService,
                    discoverService: dependencies.seerrDiscoverService,
                    userID: userID
                )
                Task { await viewModel?.loadContent() }
            } else if viewModel?.needsReload == true {
                viewModel?.needsReload = false
                Task { await viewModel?.loadContent() }
            } else if let last = viewModel?.lastLoadedAt,
                      Date().timeIntervalSince(last) > Self.refreshStaleSeconds {
                // Pick up new server-side content (Latest Movies,
                // Latest Series, …) when the user comes back to Home
                // after a while. 60 s is tight enough that fresh
                // additions show up quickly and loose enough that
                // rapid tab-hopping doesn't spam the server.
                Task { await viewModel?.loadContent() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeConfigDidChange)) { _ in
            viewModel?.reloadConfig()
            viewModel?.needsReload = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeFavoritesDidChange)) { _ in
            Task { await viewModel?.loadContent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackProgressDidChange)) { _ in
            // The Jellyfin server has fresh progress for whatever
            // the user just watched. Reload so Continue Watching and
            // Next Up reflect it as soon as the user is back here.
            Task { await viewModel?.loadContent() }
        }
        .onChange(of: appState.activeUser?.id) { _, newValue in
            // Profile switch — tear down the old HomeViewModel so the
            // next .onAppear rebuilds it with the new userID. Leaving
            // the old one around would keep loading content for the
            // previous profile's permissions + watch state.
            guard let userID = newValue else {
                viewModel = nil
                return
            }
            viewModel = HomeViewModel(
                libraryService: dependencies.jellyfinLibraryService,
                imageService: dependencies.jellyfinImageService,
                discoverService: dependencies.seerrDiscoverService,
                userID: userID
            )
            Task { await viewModel?.loadContent() }
        }
    }

    private func contentView(vm: HomeViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 40) {
                ForEach(vm.orderedSections()) { section in
                    switch section {
                    case .media(let row):
                        HorizontalMediaRow(
                            title: row.type.localizedTitle,
                            items: row.items,
                            imageURLProvider: { vm.imageURL(for: $0, rowType: row.type) },
                            onItemSelected: { selectedItem = $0 },
                            cardStyle: row.type.cardStyle
                        )

                    case .tags(let tagRow):
                        TagRow(
                            title: tagRow.type.localizedTitle,
                            tags: tagRow.tags,
                            onTagSelected: { tagData in
                                selectedFilter = makeFilter(for: tagData, type: tagRow.type)
                            }
                        )

                    case .discoverProviders:
                        // Hide tiles whose resolved match count is
                        // zero. The view-model precomputes counts in
                        // the background (so the filter activates
                        // automatically without requiring the user
                        // to tap each tile first); a `nil` count
                        // means "not yet computed" and shows the
                        // tile, so first-run sees everything until
                        // the precompute fills in the dict and empty
                        // tiles fade out a few seconds later. Once
                        // the user adds matching content the tile
                        // re-appears on the next session — the
                        // precompute reruns and the count climbs
                        // above zero.
                        let visibleProviders = CatalogProviders.networks.filter { provider in
                            let count = vm.providerItemCounts[provider.id]
                            return count == nil || count! > 0
                        }
                        if !visibleProviders.isEmpty {
                            CatalogProviderRow(
                                titleKey: HomeRowType.discoverProviders.localizedTitle,
                                providers: visibleProviders,
                                onSelect: { provider in
                                    selectedFilter = makeJellyfinFilter(for: provider)
                                },
                                backdropFor: { provider in
                                    vm.providerBackdrops[provider.id]
                                }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 40)
        }
    }

    private func makeJellyfinFilter(for provider: CatalogProvider) -> FilterDestination {
        // Tap on a Netflix/Disney+/… tile filters the *local* library
        // by Studio rather than pushing the Jellyseerr discover page.
        // Multiple aliases are pipe-joined in JellyfinEndpoints, so a
        // user whose scraper tagged some items "Disney+" and others
        // "Walt Disney Pictures" gets both in one row. The smart-
        // provider hint augments that with TMDB's live watch-provider
        // data so titles whose Studios tag doesn't betray the streamer
        // still surface (Modern Family on Disney+, Bluey via Ludo
        // Studio, …).
        let region = Locale.current.region?.identifier ?? "US"
        return FilterDestination(
            title: provider.name,
            query: ItemQuery(
                includeItemTypes: [.movie, .series],
                sortBy: "SortName",
                sortOrder: "Ascending",
                limit: 200,
                studioNames: provider.jellyfinStudioNames
            ),
            smartProviderID: provider.tmdbWatchProviderID,
            smartProviderRegion: region,
            cacheKey: HomeView.providerCacheKey(provider: provider, region: region)
        )
    }

    /// Convenience that pulls the right key out of the central
    /// `FilterCacheKey.Home` namespace — kept here so existing call
    /// sites that pass a `CatalogProvider` don't have to reach into
    /// the provider's id field themselves.
    static func providerCacheKey(provider: CatalogProvider, region: String) -> String {
        FilterCacheKey.Home.provider(id: provider.id, region: region)
    }

    private func makeFilter(for tag: TagCardData, type: HomeRowType) -> FilterDestination {
        switch type {
        case .genres:
            FilterDestination(
                title: tag.name,
                query: ItemQuery(
                    includeItemTypes: [.movie, .series],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 50,
                    genres: [tag.name]
                ),
                // Without a cacheKey FilteredGridView's init() falls
                // through to the empty-state branch and shows
                // isLoading=true on every visit — that's the "lädt
                // kurz" the user perceives every time they open a
                // genre tile. Tag name is the differentiator (Action,
                // Comedy, Drama, …) so it's a stable enough key.
                cacheKey: FilterCacheKey.Home.genre(name: tag.name)
            )
        default:
            FilterDestination(
                title: tag.name,
                query: ItemQuery(),
                cacheKey: FilterCacheKey.Home.tag(name: tag.name)
            )
        }
    }
}

struct FilterDestination: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let query: ItemQuery
    /// Optional TMDB watch-provider id used to augment the studio-
    /// name filter with the live "what's actually streaming on this
    /// service right now" list from Jellyseerr — picks up titles
    /// whose Studios tag in Jellyfin doesn't betray the streamer
    /// (Modern Family on Disney+, Bluey via Ludo Studio, Suits on
    /// Netflix even though the studio is Universal, …). nil → only
    /// the studio match runs.
    var smartProviderID: Int?
    /// ISO 3166-1 alpha-2 region used with `smartProviderID`. TMDB's
    /// watch-provider data is region-specific (Disney+ in DE has
    /// different titles than Disney+ in US), so we always pin to a
    /// concrete region — defaulting to the user's `Locale.current`.
    var smartProviderRegion: String?
    /// Stable identifier under which FilteredGridView caches its
    /// final result. Set independently of `smartProviderID` so that
    /// broadcast-only tiles (ABC / NBC / CBS — no watch-provider
    /// concept) still cache their results and feed the empty-tile-
    /// hide pass on the next visit.
    var cacheKey: String?
}

extension ItemQuery: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(parentID)
        hasher.combine(sortBy)
        hasher.combine(genres)
        hasher.combine(studioNames)
    }

    static func == (lhs: ItemQuery, rhs: ItemQuery) -> Bool {
        lhs.parentID == rhs.parentID &&
        lhs.sortBy == rhs.sortBy &&
        lhs.genres == rhs.genres &&
        lhs.studioNames == rhs.studioNames &&
        lhs.isFavorite == rhs.isFavorite
    }
}
