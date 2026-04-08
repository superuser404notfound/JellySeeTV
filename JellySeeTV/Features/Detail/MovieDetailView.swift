import SwiftUI

struct MovieDetailView: View {
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

            // Gradient overlay
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
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(vm.item.name)
                .font(.title)
                .fontWeight(.bold)

            // Metadata row
            HStack(spacing: 16) {
                if let year = vm.item.productionYear {
                    Text(String(year))
                        .foregroundStyle(.secondary)
                }
                if let runtime = vm.item.runTimeTicks {
                    Text(runtime.ticksToDisplay)
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

            // Genres
            if let genres = vm.item.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Overview
            if let overview = vm.item.overview {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            // Cast
            if let people = vm.item.people?.prefix(5), !people.isEmpty {
                Text(people.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 50)
        .padding(.top, 24)
    }
}
