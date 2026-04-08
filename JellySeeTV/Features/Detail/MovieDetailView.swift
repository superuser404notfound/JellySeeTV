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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Backdrop + Glass Panel overlay
                backdropWithPanel(vm: vm)

                // Content below the hero
                VStack(alignment: .leading, spacing: 40) {
                    // Overview
                    if let overview = vm.item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                            .padding(.horizontal, 50)
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
                .padding(.top, 32)
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Backdrop + Glass Panel

    private func backdropWithPanel(vm: DetailViewModel) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed backdrop
            AsyncCachedImage(url: vm.backdropURL(for: vm.item)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.Theme.surface)
            }
            .frame(height: 650)
            .clipped()

            // Gradient overlays
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 350)
            }

            // Glass info panel
            glassPanel(vm: vm)
                .padding(.horizontal, 50)
                .padding(.bottom, 40)
        }
        .frame(height: 650)
    }

    private func glassPanel(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(vm.item.name)
                .font(.title)
                .fontWeight(.bold)

            // Episode subtitle
            if vm.item.type == .episode {
                if let series = vm.item.seriesName {
                    Text(episodeSubtitle(vm: vm, seriesName: series))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Metadata row
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

    private func playButtonTitle(vm: DetailViewModel) -> LocalizedStringKey {
        if let ticks = vm.item.userData?.playbackPositionTicks, ticks > 0 {
            return "detail.resume"
        }
        return "detail.play"
    }

    private func episodeSubtitle(vm: DetailViewModel, seriesName: String) -> String {
        var parts = [seriesName]
        if let s = vm.item.parentIndexNumber {
            parts.append("S\(s)")
        }
        if let e = vm.item.indexNumber {
            parts.append("E\(e)")
        }
        return parts.joined(separator: " · ")
    }
}
