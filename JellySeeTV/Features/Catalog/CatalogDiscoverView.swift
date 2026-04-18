import SwiftUI

struct CatalogDiscoverView: View {
    @Bindable var viewModel: CatalogViewModel
    var onSelect: (SeerrMedia) -> Void

    var body: some View {
        Group {
            if viewModel.isLoadingDiscover && viewModel.trending.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.trending.isEmpty {
                errorState(message: error)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 40) {
                        if !viewModel.trending.isEmpty {
                            SeerrHorizontalMediaRow(
                                title: "catalog.section.trending",
                                items: viewModel.trending,
                                onItemSelected: onSelect
                            )
                        }
                        if !viewModel.popularMovies.isEmpty {
                            SeerrHorizontalMediaRow(
                                title: "catalog.section.popularMovies",
                                items: viewModel.popularMovies,
                                onItemSelected: onSelect
                            )
                        }
                        if !viewModel.popularTV.isEmpty {
                            SeerrHorizontalMediaRow(
                                title: "catalog.section.popularShows",
                                items: viewModel.popularTV,
                                onItemSelected: onSelect
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
