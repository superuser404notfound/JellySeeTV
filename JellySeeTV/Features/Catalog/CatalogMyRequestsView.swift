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
                            SeerrRequestRow(request: request)
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

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    SeerrRequestStatusBadge(status: request.status)
                    if let mediaStatus = request.media?.status {
                        SeerrStatusBadge(status: mediaStatus)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }

    private var icon: String {
        switch request.type {
        case .movie: "film"
        case .tv: "tv"
        case .person: "person"
        }
    }

    private var title: String {
        let typeLabel: String = switch request.type {
        case .movie:
            String(localized: "catalog.request.movie", defaultValue: "Movie Request")
        case .tv:
            String(localized: "catalog.request.tv", defaultValue: "Series Request")
        case .person:
            ""
        }
        return "\(typeLabel) · #\(request.id)"
    }
}
