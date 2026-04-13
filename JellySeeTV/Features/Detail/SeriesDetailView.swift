import SwiftUI

struct SeriesDetailView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: DetailViewModel?
    @State private var selectedEpisode: JellyfinItem?
    @State private var navigateToItem: JellyfinItem?
    @State private var backdropURL: URL?
    @State private var showPlayer = false
    @State private var playItem: JellyfinItem?
    @State private var playFromBeginning = false
    @FocusState private var focusedSeasonID: String?
    @FocusState private var focusedEpisodeID: String?
    @State private var episodeRedirectDone = false

    let item: JellyfinItem

    private var displayItem: JellyfinItem {
        selectedEpisode ?? viewModel?.item ?? item
    }

    private var isShowingEpisode: Bool {
        selectedEpisode != nil
    }

    var body: some View {
        ZStack {
            DetailBackdrop(imageURL: backdropURL)
                .id(backdropURL?.absoluteString ?? "empty")

            if let vm = viewModel {
                DetailContentOverlay {
                    glassPanel(vm: vm)
                        .padding(.horizontal, 50)
                        .id("\(vm.item.id)-\(vm.item.genres?.count ?? 0)-\(vm.isLoading)")
                        .animation(.easeInOut(duration: 0.3), value: selectedEpisode?.id)

                    if let overview = displayItem.overview, !overview.isEmpty {
                        ExpandableTextBox(text: overview)
                            .padding(.horizontal, 50)
                            .id(displayItem.id)
                    }

                    if displayItem.mediaStreams != nil || displayItem.mediaSources != nil {
                        TechInfoBox(item: displayItem)
                            .animation(.easeInOut(duration: 0.3), value: selectedEpisode?.id)
                    }

                    if !vm.seasons.isEmpty {
                        seasonSection(vm: vm)
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
            } else {
                ProgressView()
            }
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showPlayer) {
            if let ep = playItem, let userID = appState.activeUser?.id {
                PlayerView(
                    item: ep,
                    startFromBeginning: playFromBeginning,
                    playbackService: dependencies.jellyfinPlaybackService,
                    userID: userID,
                    cachedPlaybackInfo: (viewModel?.currentEpisodeID == ep.id) ? viewModel?.cachedPlaybackInfo : nil,
                    onDismiss: { showPlayer = false }
                )
                .ignoresSafeArea()
            }
        }
        .navigationDestination(item: $navigateToItem) { item in
            DetailRouterView(item: item)
        }
        .onAppear {
            if viewModel == nil, let userID = appState.activeUser?.id {
                viewModel = DetailViewModel(
                    item: item,
                    itemService: dependencies.jellyfinItemService,
                    imageService: dependencies.jellyfinImageService,
                    userID: userID,
                    libraryService: dependencies.jellyfinLibraryService,
                    playbackService: dependencies.jellyfinPlaybackService
                )
                Task {
                    await viewModel?.loadFullDetail()
                    updateBackdropURL()
                    await viewModel?.loadSeasons()
                }
            }
        }
        .onChange(of: viewModel?.isLoading) { _, _ in updateBackdropURL() }
        .onChange(of: selectedEpisode?.id) { _, _ in updateBackdropURL() }
    }

    private func updateBackdropURL() {
        if let ep = selectedEpisode {
            backdropURL = dependencies.jellyfinImageService.episodeThumbnailURL(for: ep)
                ?? viewModel.flatMap { $0.backdropURL(for: $0.item) }
        } else {
            backdropURL = viewModel.flatMap { $0.backdropURL(for: $0.item) }
        }
    }

    // MARK: - Glass Panel

    private func glassPanel(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if isShowingEpisode {
                Text(vm.item.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(isShowingEpisode ? (selectedEpisode?.name ?? "") : vm.item.name)
                .font(.largeTitle)
                .fontWeight(.bold)

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
                ItemMetadataRow(item: vm.item, showRuntime: false) {
                    if let count = vm.item.childCount, count > 0 {
                        AnyView(Text("detail.seasonCount \(count)"))
                    } else {
                        AnyView(EmptyView())
                    }
                }
            }

            if let genres = vm.item.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                GlassActionButton(
                    title: playTitle,
                    systemImage: "play.fill",
                    isProminent: true,
                    action: {
                        let ep = selectedEpisode ?? vm.episodes.first(where: { $0.id == vm.currentEpisodeID }) ?? vm.episodes.first
                        if let ep {
                            playItem = ep
                            playFromBeginning = false
                            showPlayer = true
                        }
                    }
                )

                if !isShowingEpisode {
                    GlassActionButton(
                        title: vm.isFavorite ? "detail.unfavorite" : "detail.favorite",
                        systemImage: vm.isFavorite ? "heart.fill" : "heart",
                        action: { Task { await vm.toggleFavorite() } }
                    )
                }

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

    // MARK: - Season Section

    private func seasonSection(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.seasons) { season in
                            SeasonTab(
                                id: season.id,
                                name: season.name,
                                isSelected: vm.selectedSeasonID == season.id,
                                focusedID: $focusedSeasonID,
                                action: {
                                    selectedEpisode = nil
                                    Task { await vm.loadEpisodes(seasonID: season.id) }
                                }
                            )
                            .id(season.id)
                        }
                    }
                    .padding(.horizontal, 50)
                }
                .onChange(of: focusedSeasonID) { oldID, newID in
                    if oldID == nil && newID != nil && newID != vm.selectedSeasonID {
                        focusedSeasonID = vm.selectedSeasonID
                    }
                    if let focusedID = focusedSeasonID {
                        withAnimation { proxy.scrollTo(focusedID, anchor: .center) }
                    }
                    if newID != nil {
                        episodeRedirectDone = false
                    }
                }
                .onChange(of: vm.selectedSeasonID) { _, newID in
                    episodeRedirectDone = false
                    withAnimation { proxy.scrollTo(newID, anchor: .center) }
                }
            }

            if !vm.episodes.isEmpty {
                ScrollViewReader { episodeProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 24) {
                            ForEach(vm.episodes) { episode in
                                Button {
                                    playItem = episode
                                    playFromBeginning = false
                                    showPlayer = true
                                } label: {
                                    EpisodeLandscapeCard(
                                        episode: episode,
                                        imageURL: dependencies.jellyfinImageService.episodeThumbnailURL(for: episode),
                                        isSelected: selectedEpisode?.id == episode.id,
                                        isCurrent: vm.currentEpisodeID == episode.id
                                    )
                                }
                                .buttonStyle(EpisodeCardButtonStyle())
                                .focused($focusedEpisodeID, equals: episode.id)
                                .id(episode.id)
                                .contextMenu {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            selectedEpisode = episode
                                        }
                                    } label: {
                                        Label("detail.episode.showDetails", systemImage: "info.circle")
                                    }

                                    Button {
                                        playItem = episode
                                        playFromBeginning = true
                                        showPlayer = true
                                    } label: {
                                        Label("detail.play", systemImage: "play.fill")
                                    }

                                    if let ticks = episode.userData?.playbackPositionTicks, ticks > 0 {
                                        Button {
                                            playItem = episode
                                            playFromBeginning = false
                                            showPlayer = true
                                        } label: {
                                            Label("detail.resume", systemImage: "play.circle")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 50)
                        .padding(.vertical, 16)
                    }
                    .onChange(of: vm.selectedSeasonID) { _, _ in
                        if let first = vm.episodes.first {
                            episodeProxy.scrollTo(first.id, anchor: .leading)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            scrollToCurrentEpisode(proxy: episodeProxy, vm: vm)
                        }
                    }
                    .onChange(of: focusedEpisodeID) { _, newID in
                        if newID != nil && !episodeRedirectDone {
                            episodeRedirectDone = true
                            if let currentID = vm.currentEpisodeID,
                               newID != currentID,
                               vm.episodes.contains(where: { $0.id == currentID }) {
                                focusedEpisodeID = currentID
                            }
                        }
                    }
                    .onAppear {
                        scrollToCurrentEpisode(proxy: episodeProxy, vm: vm)
                    }
                }
            }
        }
    }

    private func scrollToCurrentEpisode(proxy: ScrollViewProxy, vm: DetailViewModel) {
        guard let currentID = vm.currentEpisodeID,
              vm.episodes.contains(where: { $0.id == currentID }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(currentID, anchor: .center)
            }
        }
    }
}

// MARK: - Season Tab

struct SeasonTab: View {
    let id: String
    let name: String
    let isSelected: Bool
    var focusedID: FocusState<String?>.Binding
    let action: () -> Void

    private var isFocused: Bool { focusedID.wrappedValue == id }

    var body: some View {
        Button { action() } label: {
            VStack(spacing: 6) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)

                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(height: 3)
                    .padding(.horizontal, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(tabBackground)
            )
        }
        .buttonStyle(SeasonTabButtonStyle())
        .focused(focusedID, equals: id)
    }

    private var tabBackground: Color {
        if isFocused { return .white.opacity(0.12) }
        if isSelected { return .white.opacity(0.08) }
        return .clear
    }
}

// MARK: - Button Styles

struct EpisodeCardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 20, y: 10)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

struct SeasonTabButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Episode Landscape Card

struct EpisodeLandscapeCard: View {
    let episode: JellyfinItem
    let imageURL: URL?
    var isSelected: Bool = false
    var isCurrent: Bool = false

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
                        .stroke(borderColor, lineWidth: isCurrent ? 3 : 2)
                )

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

    private var borderColor: Color {
        if isSelected { return .accentColor.opacity(0.8) }
        if isCurrent { return .green.opacity(0.8) }
        return .clear
    }
}
