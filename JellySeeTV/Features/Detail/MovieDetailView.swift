import SwiftUI

struct MovieDetailView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: DetailViewModel?

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
            // Fullscreen backdrop
            backdrop(vm: vm)

            // Scrollable content overlay
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Spacer to push content below the visible backdrop area
                    Color.clear.frame(height: 500)

                    // Gradient transition
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)

                    // Content on solid black
                    VStack(alignment: .leading, spacing: 40) {
                        // Glass info panel
                        glassPanel(vm: vm)
                            .padding(.horizontal, 50)

                        // Overview
                        if let overview = vm.item.overview, !overview.isEmpty {
                            ExpandableTextBox(text: overview)
                                .padding(.horizontal, 50)
                        }

                        // Tech info
                        if vm.item.mediaStreams != nil || vm.item.mediaSources != nil {
                            TechInfoBox(item: vm.item)
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

                        // Similar items
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

    // MARK: - Fullscreen Backdrop

    private func backdrop(vm: DetailViewModel) -> some View {
        AsyncCachedImage(url: vm.backdropURL(for: vm.item)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Color.Theme.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(
            Color.black.opacity(0.3)
        )
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

            // Metadata
            metadataRow(vm: vm)

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
                    action: { /* Phase 3: Playback */ }
                )

                if hasProgress(vm: vm) {
                    GlassActionButton(
                        title: "detail.replay",
                        systemImage: "arrow.counterclockwise",
                        action: { /* Phase 3: Replay from start */ }
                    )
                }

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

    // MARK: - Helpers

    private func metadataRow(vm: DetailViewModel) -> some View {
        HStack(spacing: 12) {
            if let year = vm.item.productionYear {
                Text(String(year))
            }
            if let runtime = vm.item.runTimeTicks {
                Text("·").foregroundStyle(.tertiary)
                Text(runtime.ticksToDisplay)
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
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

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
