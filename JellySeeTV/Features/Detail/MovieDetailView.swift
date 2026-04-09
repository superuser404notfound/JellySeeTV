import SwiftUI

struct MovieDetailView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: DetailViewModel?
    @State private var navigateToSeries: JellyfinItem?
    @State private var navigateToItem: JellyfinItem?
    @State private var showPlayer = false
    @State private var playFromBeginning = false

    let item: JellyfinItem

    var body: some View {
        Group {
            if let vm = viewModel {
                contentView(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .overlay {
            if showPlayer, let userID = appState.activeUser?.id {
                PlayerView(
                    item: viewModel?.item ?? item,
                    startFromBeginning: playFromBeginning,
                    playbackService: dependencies.jellyfinPlaybackService,
                    userID: userID,
                    onDismiss: { showPlayer = false }
                )
                .transition(.opacity)
                .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showPlayer)
        .navigationDestination(item: $navigateToItem) { item in
            DetailRouterView(item: item)
        }
        .navigationDestination(item: $navigateToSeries) { series in
            SeriesDetailView(item: series)
                .toolbar(.hidden, for: .tabBar)
        }
        .onAppear {
            if viewModel == nil, let userID = appState.activeUser?.id {
                viewModel = DetailViewModel(
                    item: item,
                    itemService: dependencies.jellyfinItemService,
                    imageService: dependencies.jellyfinImageService,
                    userID: userID
                )
                Task { await viewModel?.loadFullDetail() }
            }
        }
    }

    private func contentView(vm: DetailViewModel) -> some View {
        ZStack {
            DetailBackdrop(imageURL: vm.backdropURL(for: vm.item))
                .id(vm.item.backdropImageTags?.first ?? "empty")

            DetailContentOverlay {
                glassPanel(vm: vm)
                    .padding(.horizontal, 50)
                    .id(vm.item.genres?.first ?? vm.item.name)

                if let overview = vm.item.overview, !overview.isEmpty {
                    ExpandableTextBox(text: overview)
                        .padding(.horizontal, 50)
                }

                if vm.item.mediaStreams != nil || vm.item.mediaSources != nil {
                    TechInfoBox(item: vm.item)
                }

                if let people = vm.item.people, !people.isEmpty {
                    CastRow(
                        people: Array(people.prefix(15)),
                        imageURLProvider: { person in
                            dependencies.jellyfinImageService.personImageURL(
                                personID: person.id,
                                tag: person.primaryImageTag
                            )
                        }
                    )
                }

                if !vm.similarItems.isEmpty {
                    HorizontalMediaRow(
                        title: "detail.similar",
                        items: vm.similarItems,
                        imageURLProvider: { vm.posterURL(for: $0) },
                        onItemSelected: { navigateToItem = $0 },
                        cardStyle: .poster
                    )
                }
            }
        }
    }

    // MARK: - Glass Panel

    private func glassPanel(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(vm.item.name)
                .font(.largeTitle)
                .fontWeight(.bold)

            // Episode subtitle
            if vm.item.type == .episode, let series = vm.item.seriesName {
                Text(episodeSubtitle(vm: vm, seriesName: series))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            ItemMetadataRow(item: vm.item)

            // Genres
            if let genres = vm.item.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 16) {
                GlassActionButton(
                    title: playButtonTitle(vm: vm),
                    systemImage: "play.fill",
                    isProminent: true,
                    action: {
                        playFromBeginning = false
                        showPlayer = true
                    }
                )

                if hasProgress(vm: vm) {
                    GlassActionButton(
                        title: "detail.replay",
                        systemImage: "arrow.counterclockwise",
                        action: {
                            playFromBeginning = true
                            showPlayer = true
                        }
                    )
                }

                if vm.item.type != .episode {
                    GlassActionButton(
                        title: vm.isFavorite ? "detail.unfavorite" : "detail.favorite",
                        systemImage: vm.isFavorite ? "heart.fill" : "heart",
                        action: { Task { await vm.toggleFavorite() } }
                    )
                }

                if vm.item.type == .episode, let seriesId = vm.item.seriesId {
                    GlassActionButton(
                        title: "detail.showSeries",
                        systemImage: "tv",
                        action: {
                            navigateToSeries = JellyfinItem(
                                seriesStub: seriesId,
                                name: vm.item.seriesName ?? ""
                            )
                        }
                    )
                }
            }
            .padding(.top, 4)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Helpers

    private func hasProgress(vm: DetailViewModel) -> Bool {
        if let ticks = vm.item.userData?.playbackPositionTicks, ticks > 0 { return true }
        return false
    }

    private func playButtonTitle(vm: DetailViewModel) -> LocalizedStringKey {
        if hasProgress(vm: vm) { return "detail.resume" }
        return "detail.play"
    }

    private func episodeSubtitle(vm: DetailViewModel, seriesName: String) -> String {
        var parts = [seriesName]
        if let s = vm.item.parentIndexNumber { parts.append("S\(s)") }
        if let e = vm.item.indexNumber { parts.append("E\(e)") }
        return parts.joined(separator: " · ")
    }
}
