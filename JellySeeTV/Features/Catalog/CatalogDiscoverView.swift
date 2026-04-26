import SwiftUI

struct CatalogDiscoverView: View {
    @Bindable var viewModel: CatalogViewModel
    var onSelect: (SeerrMedia) -> Void
    var onSelectFilter: (CatalogFilter) -> Void

    var body: some View {
        Group {
            if viewModel.isLoadingDiscover && viewModel.trending.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.trending.items.isEmpty {
                errorState(message: error)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 40) {
                        if !viewModel.trending.items.isEmpty {
                            SeerrHorizontalMediaRow(
                                title: "catalog.section.trending",
                                items: viewModel.trending.items,
                                isLoadingMore: viewModel.trending.isLoading,
                                onItemSelected: onSelect,
                                onNeedsMore: {
                                    Task { await viewModel.loadMore(row: .trending) }
                                }
                            )
                        }
                        if !viewModel.upcomingMovies.items.isEmpty {
                            SeerrHorizontalMediaRow(
                                title: "catalog.section.upcomingMovies",
                                items: viewModel.upcomingMovies.items,
                                isLoadingMore: viewModel.upcomingMovies.isLoading,
                                onItemSelected: onSelect,
                                onNeedsMore: {
                                    Task { await viewModel.loadMore(row: .upcomingMovies) }
                                }
                            )
                        }
                        if !viewModel.upcomingTV.items.isEmpty {
                            SeerrHorizontalMediaRow(
                                title: "catalog.section.upcomingShows",
                                items: viewModel.upcomingTV.items,
                                isLoadingMore: viewModel.upcomingTV.isLoading,
                                onItemSelected: onSelect,
                                onNeedsMore: {
                                    Task { await viewModel.loadMore(row: .upcomingTV) }
                                }
                            )
                        }
                        if !viewModel.popularMovies.items.isEmpty {
                            SeerrHorizontalMediaRow(
                                title: "catalog.section.popularMovies",
                                items: viewModel.popularMovies.items,
                                isLoadingMore: viewModel.popularMovies.isLoading,
                                onItemSelected: onSelect,
                                onNeedsMore: {
                                    Task { await viewModel.loadMore(row: .movies) }
                                }
                            )
                        }
                        if !viewModel.popularTV.items.isEmpty {
                            SeerrHorizontalMediaRow(
                                title: "catalog.section.popularShows",
                                items: viewModel.popularTV.items,
                                isLoadingMore: viewModel.popularTV.isLoading,
                                onItemSelected: onSelect,
                                onNeedsMore: {
                                    Task { await viewModel.loadMore(row: .tv) }
                                }
                            )
                        }
                        if !viewModel.movieGenres.isEmpty {
                            CatalogGenreRow(
                                titleKey: "catalog.section.movieGenres",
                                genres: viewModel.movieGenres,
                                kind: .movie,
                                onSelect: onSelectFilter
                            )
                        }
                        if !viewModel.tvGenres.isEmpty {
                            CatalogGenreRow(
                                titleKey: "catalog.section.tvGenres",
                                genres: viewModel.tvGenres,
                                kind: .tv,
                                onSelect: onSelectFilter
                            )
                        }
                        // Networks row — drop tiles whose cached
                        // first page is empty so the user isn't
                        // teased with a card that opens to nothing.
                        let region = Locale.current.region?.identifier ?? "US"
                        let visibleNetworks = CatalogProviders.networks.filter { provider in
                            let key: String
                            if let id = provider.tmdbWatchProviderID {
                                key = FilterCacheKey.Catalog.streamingService(
                                    watchProviderID: id, region: region
                                )
                            } else {
                                key = FilterCacheKey.Catalog.tvNetwork(id: provider.id)
                            }
                            let count = FilterCache.shared.catalogPage(filterKey: key)?.items.count
                            return count == nil || count! > 0
                        }
                        if !visibleNetworks.isEmpty {
                            CatalogProviderRow(
                                titleKey: "catalog.section.networks",
                                providers: visibleNetworks,
                                onSelect: { provider in
                                    // Prefer the live watch-providers
                                    // filter (movies + tv together)
                                    // when we know the streamer's
                                    // TMDB id; fall back to the
                                    // TV-only network endpoint for
                                    // broadcast networks (ABC, NBC,
                                    // CBS) without one.
                                    if let providerID = provider.tmdbWatchProviderID {
                                        onSelectFilter(.streamingService(
                                            tmdbWatchProviderID: providerID,
                                            name: provider.name,
                                            region: region
                                        ))
                                    } else {
                                        onSelectFilter(.tvNetwork(id: provider.id, name: provider.name))
                                    }
                                },
                                backdropFor: { provider in
                                    SeerrImageURL.backdrop(path: viewModel.networkBackdrops[provider.id], size: .w780)
                                }
                            )
                        }
                        let visibleStudios = CatalogProviders.studios.filter { provider in
                            let key = FilterCacheKey.Catalog.movieStudio(id: provider.id)
                            let count = FilterCache.shared.catalogPage(filterKey: key)?.items.count
                            return count == nil || count! > 0
                        }
                        if !visibleStudios.isEmpty {
                            CatalogProviderRow(
                                titleKey: "catalog.section.studios",
                                providers: visibleStudios,
                                onSelect: { provider in
                                    onSelectFilter(.movieStudio(id: provider.id, name: provider.name))
                                },
                                backdropFor: { provider in
                                    SeerrImageURL.backdrop(path: viewModel.studioBackdrops[provider.id], size: .w780)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 40)
                }
            }
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("home.retry") {
                Task { await viewModel.loadDiscover() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
