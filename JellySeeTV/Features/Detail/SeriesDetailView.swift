import SwiftUI

struct SeriesDetailView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: DetailViewModel?

    let item: JellyfinItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let vm = viewModel {
                    backdropHeader(vm: vm)
                    infoSection(vm: vm)
                    seasonPicker(vm: vm)
                    episodeList(vm: vm)

                    if !vm.similarItems.isEmpty {
                        HorizontalMediaRow(
                            title: "detail.similar",
                            items: vm.similarItems,
                            imageURLProvider: { vm.posterURL(for: $0) }
                        )
                        .padding(.top, 40)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
                Task {
                    await viewModel?.loadFullDetail()
                    await viewModel?.loadSeasons()
                }
            }
        }
    }

    private func backdropHeader(vm: DetailViewModel) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncCachedImage(url: vm.backdropURL(for: vm.item)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.Theme.surface)
            }
            .frame(height: 500)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 500)
    }

    private func infoSection(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(vm.item.name)
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                if let year = vm.item.productionYear {
                    Text(String(year))
                        .foregroundStyle(.secondary)
                }
                if let rating = vm.item.officialRating {
                    Text(rating)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.secondary, lineWidth: 1)
                        )
                }
                if let score = vm.item.communityRating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(String(format: "%.1f", score))
                    }
                }
            }

            if let genres = vm.item.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let overview = vm.item.overview {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.horizontal, 50)
        .padding(.top, 24)
    }

    private func seasonPicker(vm: DetailViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(vm.seasons) { season in
                    Button {
                        Task { await vm.loadEpisodes(seasonID: season.id) }
                    } label: {
                        Text(season.name)
                            .font(.subheadline)
                            .fontWeight(vm.selectedSeasonID == season.id ? .bold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 50)
        }
        .padding(.top, 24)
    }

    private func episodeList(vm: DetailViewModel) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(vm.episodes) { episode in
                EpisodeRow(episode: episode, imageURL: vm.posterURL(for: episode))
            }
        }
        .padding(.horizontal, 50)
        .padding(.top, 16)
    }
}

struct EpisodeRow: View {
    let episode: JellyfinItem
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 16) {
            AsyncCachedImage(url: imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.Theme.surface)
            }
            .frame(width: 200, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let num = episode.indexNumber {
                        Text("E\(num)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(episode.name)
                        .font(.body)
                        .lineLimit(1)
                }

                if let runtime = episode.runTimeTicks {
                    Text(runtime.ticksToDisplay)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let overview = episode.overview {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if episode.userData?.played == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}
