import SwiftUI

struct SeriesDetailView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: DetailViewModel?
    @State private var selectedEpisode: JellyfinItem?
    @State private var navigateToEpisode: JellyfinItem?

    let item: JellyfinItem

    /// The item to show in the info panel -- selected episode or series itself
    private var displayItem: JellyfinItem {
        selectedEpisode ?? viewModel?.item ?? item
    }

    private var isShowingEpisode: Bool {
        selectedEpisode != nil
    }

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
        .navigationDestination(item: $navigateToEpisode) { ep in
            DetailRouterView(item: ep)
        }
        .onAppear {
            if viewModel == nil, let userID = appState.activeUser?.id {
                viewModel = DetailViewModel(
                    item: item,
                    itemService: dependencies.jellyfinItemService,
                    imageService: dependencies.jellyfinImageService,
                    userID: userID
                )
                Task {
                    await viewModel?.loadFullDetail()
                    await viewModel?.loadSeasons()
                }
            }
        }
    }

    private func contentView(vm: DetailViewModel) -> some View {
        ZStack {
            // Fullscreen backdrop (changes with selected episode)
            backdrop(vm: vm)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 500)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)

                    VStack(alignment: .leading, spacing: 40) {
                        // Dynamic info panel
                        glassPanel(vm: vm)
                            .padding(.horizontal, 50)
                            .animation(.easeInOut(duration: 0.3), value: selectedEpisode?.id)

                        // Overview
                        if let overview = displayItem.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .padding(.horizontal, 50)
                                .animation(.easeInOut(duration: 0.3), value: selectedEpisode?.id)
                        }

                        // Tech info (from selected episode or series)
                        if displayItem.mediaStreams != nil || displayItem.mediaSources != nil {
                            TechInfoBox(item: displayItem)
                                .animation(.easeInOut(duration: 0.3), value: selectedEpisode?.id)
                        }

                        // Season picker + episodes
                        if !vm.seasons.isEmpty {
                            seasonSection(vm: vm)
                        }

                        // Cast
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

                        // Similar
                        if !vm.similarItems.isEmpty {
                            HorizontalMediaRow(
                                title: "detail.similar",
                                items: vm.similarItems,
                                imageURLProvider: { vm.posterURL(for: $0) },
                                cardStyle: .poster
                            )
                        }
                    }
                    .padding(.bottom, 80)
                    .background(.black)
                }
            }
        }
    }

    // MARK: - Backdrop

    private func backdrop(vm: DetailViewModel) -> some View {
        let backdropURL: URL? = if let ep = selectedEpisode {
            dependencies.jellyfinImageService.episodeThumbnailURL(for: ep)
                ?? vm.backdropURL(for: vm.item)
        } else {
            vm.backdropURL(for: vm.item)
        }

        return AsyncCachedImage(url: backdropURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Color.Theme.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(Color.black.opacity(0.3))
        .animation(.easeInOut(duration: 0.5), value: selectedEpisode?.id)
    }

    // MARK: - Glass Panel (dynamic)

    private func glassPanel(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Series title always shown
            if isShowingEpisode {
                Text(vm.item.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Main title
            Text(isShowingEpisode ? (selectedEpisode?.name ?? "") : vm.item.name)
                .font(.largeTitle)
                .fontWeight(.bold)

            // Episode info
            if isShowingEpisode, let ep = selectedEpisode {
                HStack(spacing: 8) {
                    if let s = ep.parentIndexNumber {
                        Text("S\(s)")
                            .fontWeight(.semibold)
                    }
                    if let e = ep.indexNumber {
                        Text("E\(e)")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                    if let runtime = ep.runTimeTicks {
                        Text("·").foregroundStyle(.tertiary)
                        Text(runtime.ticksToDisplay)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                // Series metadata
                seriesMetadata(vm: vm)
            }

            // Genres (series always)
            if let genres = vm.item.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 16) {
                GlassActionButton(
                    title: playTitle,
                    systemImage: "play.fill",
                    isProminent: true,
                    action: { /* Phase 3 */ }
                )

                GlassActionButton(
                    title: vm.item.userData?.isFavorite == true ? "detail.unfavorite" : "detail.favorite",
                    systemImage: vm.item.userData?.isFavorite == true ? "heart.fill" : "heart",
                    action: { Task { await vm.toggleFavorite() } }
                )

                if isShowingEpisode {
                    GlassActionButton(
                        title: "detail.showSeries",
                        systemImage: "xmark",
                        action: {
                            withAnimation { selectedEpisode = nil }
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

    private var playTitle: LocalizedStringKey {
        if let ep = selectedEpisode,
           let ticks = ep.userData?.playbackPositionTicks, ticks > 0 {
            return "detail.resume"
        }
        return "detail.play"
    }

    private func seriesMetadata(vm: DetailViewModel) -> some View {
        HStack(spacing: 12) {
            if let year = vm.item.productionYear {
                Text(String(year))
            }
            if let rating = vm.item.officialRating {
                Text("·").foregroundStyle(.tertiary)
                Text(rating)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.secondary.opacity(0.5), lineWidth: 1)
                    )
            }
            if let score = vm.item.communityRating {
                Text("·").foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(String(format: "%.1f", score))
                }
            }
            if let count = vm.item.childCount, count > 0 {
                Text("·").foregroundStyle(.tertiary)
                Text("detail.seasonCount \(count)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Season Section

    private func seasonSection(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Season tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.seasons) { season in
                        SeasonTab(
                            name: season.name,
                            isSelected: vm.selectedSeasonID == season.id,
                            action: {
                                selectedEpisode = nil
                                Task { await vm.loadEpisodes(seasonID: season.id) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 50)
            }

            // Episode cards
            if !vm.episodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 24) {
                        ForEach(vm.episodes) { episode in
                            FocusableCard {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedEpisode = episode
                                }
                            } content: { _ in
                                EpisodeLandscapeCard(
                                    episode: episode,
                                    imageURL: dependencies.jellyfinImageService.episodeThumbnailURL(for: episode),
                                    isSelected: selectedEpisode?.id == episode.id
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

// MARK: - Season Tab

struct SeasonTab: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Text(name)
            .font(.subheadline)
            .fontWeight(isSelected ? .bold : .regular)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(tabBackground)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .focusable()
            .focused($isFocused)
            .onLongPressGesture(minimumDuration: 0) { action() }
    }

    private var tabBackground: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.ultraThinMaterial) }
        if isFocused { return AnyShapeStyle(.white.opacity(0.12)) }
        return AnyShapeStyle(.white.opacity(0.05))
    }
}

// MARK: - Episode Landscape Card

struct EpisodeLandscapeCard: View {
    let episode: JellyfinItem
    let imageURL: URL?
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                AsyncCachedImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.Theme.surface)
                        .overlay(
                            Image(systemName: "play.rectangle")
                                .font(.system(size: 30))
                                .foregroundStyle(.tertiary)
                        )
                }
                .frame(width: 360, height: 202)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 2)
                )

                // Progress bar
                if let pct = episode.userData?.playedPercentage, pct > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.ultraThinMaterial).frame(height: 4)
                                Rectangle().fill(.tint).frame(width: geo.size.width * pct / 100, height: 4)
                            }
                        }
                    }
                    .frame(width: 360, height: 202)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Played badge
                if episode.userData?.played == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 360, height: 202)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let ep = episode.indexNumber {
                        Text("E\(ep)")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .fontWeight(.semibold)
                    }
                    Text(episode.name)
                        .font(.caption)
                        .lineLimit(1)
                }

                if let runtime = episode.runTimeTicks {
                    Text(runtime.ticksToDisplay)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 360, alignment: .leading)
        }
    }
}
