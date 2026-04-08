import SwiftUI

struct SeriesDetailView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: DetailViewModel?
    @State private var selectedItem: JellyfinItem?

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
        .navigationDestination(item: $selectedItem) { item in
            DetailRouterView(item: item)
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                backdropWithPanel(vm: vm)

                VStack(alignment: .leading, spacing: 40) {
                    // Overview
                    if let overview = vm.item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                            .padding(.horizontal, 50)
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
                            onItemSelected: { selectedItem = $0 },
                            cardStyle: .poster
                        )
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Backdrop + Glass Panel

    private func backdropWithPanel(vm: DetailViewModel) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncCachedImage(url: vm.backdropURL(for: vm.item)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.Theme.surface)
            }
            .frame(height: 650)
            .clipped()

            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 350)
            }

            glassPanel(vm: vm)
                .padding(.horizontal, 50)
                .padding(.bottom, 40)
        }
        .frame(height: 650)
    }

    private func glassPanel(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(vm.item.name)
                .font(.title)
                .fontWeight(.bold)

            // Metadata
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

            // Genres
            if let genres = vm.item.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 16) {
                GlassActionButton(
                    title: "detail.play",
                    systemImage: "play.fill",
                    isProminent: true,
                    action: { /* Phase 3: Playback */ }
                )

                GlassActionButton(
                    title: vm.item.userData?.isFavorite == true ? "detail.unfavorite" : "detail.favorite",
                    systemImage: vm.item.userData?.isFavorite == true ? "heart.fill" : "heart",
                    action: { /* TODO: toggle favorite */ }
                )
            }
            .padding(.top, 4)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Season Section

    private func seasonSection(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Season picker tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.seasons) { season in
                        SeasonTab(
                            name: season.name,
                            isSelected: vm.selectedSeasonID == season.id,
                            action: {
                                Task { await vm.loadEpisodes(seasonID: season.id) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 50)
            }

            // Episodes as horizontal landscape cards
            if !vm.episodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 24) {
                        ForEach(vm.episodes) { episode in
                            FocusableCard {
                                selectedItem = episode
                            } content: { _ in
                                EpisodeLandscapeCard(
                                    episode: episode,
                                    imageURL: dependencies.jellyfinImageService.episodeThumbnailURL(for: episode)
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
            .onLongPressGesture(minimumDuration: 0) {
                action()
            }
    }

    private var tabBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        if isFocused {
            return AnyShapeStyle(.white.opacity(0.12))
        }
        return AnyShapeStyle(.white.opacity(0.05))
    }
}

// MARK: - Episode Landscape Card

struct EpisodeLandscapeCard: View {
    let episode: JellyfinItem
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Episode thumbnail
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

                // Played checkmark
                if episode.userData?.played == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 360, height: 202)

            // Info
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

                HStack(spacing: 8) {
                    if let runtime = episode.runTimeTicks {
                        Text(runtime.ticksToDisplay)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let overview = episode.overview {
                        Text(overview)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 360, alignment: .leading)
        }
    }
}
