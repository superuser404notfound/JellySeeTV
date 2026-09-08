import SwiftUI

struct CatalogMyRequestsView: View {
    @Environment(\.appState) private var appState
    @Bindable var viewModel: CatalogViewModel
    @State private var selectedMedia: SeerrMedia?

    var body: some View {
        Group {
            if viewModel.isLoadingRequests && viewModel.myRequests.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.myRequests.isEmpty {
                errorState(message: error)
            } else if viewModel.myRequests.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(viewModel.myRequests.enumerated()), id: \.element.id) { index, request in
                            SeerrRequestRow(
                                request: request,
                                title: viewModel.title(for: request),
                                year: viewModel.year(for: request),
                                posterURL: viewModel.posterURL(for: request),
                                onSelect: { handleSelect(request) }
                            )
                            .onAppear {
                                if index >= viewModel.myRequests.count - 5 {
                                    Task { await viewModel.loadMoreMyRequests() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 40)
                }
            }
        }
        // Full-screen cover (over the tab bar) instead of a push: the bar is never hidden/removed, so it is never re-templated gray on return (tvOS 26). See detailCover.
        .detailCover(item: $selectedMedia) { media in
            CatalogDetailView(media: media)
        }
    }

    /// Navigates back to the catalog detail via a minimal SeerrMedia stub (CatalogDetailView re-fetches on appear); skips when there's no media id so we never push an empty detail.
    private func handleSelect(_ request: SeerrRequest) {
        guard let tmdbID = request.media?.tmdbId else { return }
        let mediaType: SeerrMediaType = (request.type == .tv) ? .tv : .movie
        selectedMedia = SeerrMedia.stub(tmdbID: tmdbID, mediaType: mediaType)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("catalog.empty.noRequests")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            Button {
                guard let userID = appState.activeSeerrUser?.id else { return }
                Task { await viewModel.loadMyRequests(userID: userID) }
            } label: {
                Text("home.retry")
                    .font(.body)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
            .buttonStyle(SettingsTileButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SeerrRequestRow: View {
    let request: SeerrRequest
    let title: String?
    let year: String?
    let posterURL: URL?
    let onSelect: () -> Void

    var body: some View {
        // FocusableCard so the focus engine can land here; without a focusable child the ScrollView won't scroll on the remote.
        FocusableCard(action: onSelect) { isFocused in
            HStack(spacing: 20) {
                poster

                VStack(alignment: .leading, spacing: 6) {
                    Text(resolvedTitle)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 10) {
                        Image(systemName: typeIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(typeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let year {
                            Text("·").foregroundStyle(.tertiary)
                            Text(year)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("·").foregroundStyle(.tertiary)
                        Text("#\(request.id)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }

                    // Collapses request.status + media.status into one badge (incl. "Removed" when completed-request media was later deleted server-side).
                    SeerrEffectiveRequestBadge(request: request)
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.05))
            )
            .focusStroke(cornerRadius: 16, isFocused: isFocused)
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let posterURL {
            AsyncCachedImage(url: posterURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholderPoster
            }
            .frame(width: 64, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholderPoster
                .frame(width: 64, height: 96)
        }
    }

    private var placeholderPoster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.Theme.restFill)
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundStyle(.tint)
        }
    }

    private var typeIcon: String {
        switch request.type {
        case .movie: "film"
        case .tv: "tv"
        case .person, .unknown: "person"
        }
    }

    private var typeLabel: String {
        switch request.type {
        case .movie:
            String(localized: "catalog.request.movie", defaultValue: "Movie")
        case .tv:
            String(localized: "catalog.request.tv", defaultValue: "Series")
        case .person, .unknown:
            ""
        }
    }

    /// Real title once the detail fetch returns, else a neutral "Loading…" placeholder (the old "Movie Request · #42" read like a bug).
    private var resolvedTitle: String {
        if let title, !title.isEmpty { return title }
        return String(
            localized: "catalog.request.loadingTitle",
            defaultValue: "Loading…"
        )
    }
}
