import SwiftUI

struct CatalogMyRequestsView: View {
    @Environment(\.appState) private var appState
    @Bindable var viewModel: CatalogViewModel

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
                        ForEach(viewModel.myRequests) { request in
                            SeerrRequestRow(
                                request: request,
                                title: viewModel.title(for: request),
                                year: viewModel.year(for: request),
                                posterURL: viewModel.posterURL(for: request)
                            )
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 40)
                }
            }
        }
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
            Button("home.retry") {
                guard let userID = appState.activeSeerrUser?.id else { return }
                Task { await viewModel.loadMyRequests(userID: userID) }
            }
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

    var body: some View {
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

                HStack(spacing: 8) {
                    SeerrRequestStatusBadge(status: request.status)
                    if let mediaStatus = request.media?.status {
                        SeerrStatusBadge(status: mediaStatus)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
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
                .fill(.white.opacity(0.08))
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundStyle(.tint)
        }
    }

    private var typeIcon: String {
        switch request.type {
        case .movie: "film"
        case .tv: "tv"
        case .person: "person"
        }
    }

    private var typeLabel: String {
        switch request.type {
        case .movie:
            String(localized: "catalog.request.movie", defaultValue: "Movie")
        case .tv:
            String(localized: "catalog.request.tv", defaultValue: "Series")
        case .person:
            ""
        }
    }

    /// Show the real title once the detail fetch returns; fall back
    /// to a neutral placeholder that doesn't pretend to be final
    /// content (the old "Movie Request · #42" pretended to be a
    /// title row and looked like a bug).
    private var resolvedTitle: String {
        if let title, !title.isEmpty { return title }
        return String(
            localized: "catalog.request.loadingTitle",
            defaultValue: "Loading…"
        )
    }
}
