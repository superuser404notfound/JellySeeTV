import SwiftUI

struct CatalogDetailView: View {
    let media: SeerrMedia
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var movieDetail: SeerrMovieDetail?
    @State private var tvDetail: SeerrTVDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var selectedSeasons: Set<Int> = []
    @State private var isSubmitting = false
    @State private var didRequest = false
    @State private var requestError: String?

    // Advanced request options — populated from /service/radarr or
    // /service/sonarr. `nil` means "fall back to Seerr's server default"
    // (which is what happens when the request body omits the field).
    @State private var serviceDetails: SeerrServiceDetails?
    @State private var selectedProfileID: Int?
    @State private var selectedRootFolder: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                backdrop
                content
            }
            .padding(.bottom, 60)
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            AsyncCachedImage(url: SeerrImageURL.backdrop(path: backdropPath)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.Theme.surface)
            }
            .frame(height: 500)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 500)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(40)
        } else if let errorMessage {
            errorState(message: errorMessage)
        } else {
            detailBody
        }
    }

    private func errorState(message: String) -> some View {
        // tvOS routes the Menu button to dismiss the top navigation level
        // only when the current view has something focusable. An error
        // screen with just text has no focus → Menu exits the app instead
        // of popping back to the catalog. Retry and Back buttons fix both:
        // they claim focus and give the user a way to recover without
        // reaching for the remote.
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            HStack(spacing: 16) {
                Button {
                    Task { await load() }
                } label: {
                    Text("home.retry")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                Button {
                    dismiss()
                } label: {
                    Text("common.back")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
    }

    private var detailBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(displayTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                if let year = displayYear {
                    Text(year)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                if let status = mediaStatus, status != .unknown {
                    SeerrStatusBadge(status: status)
                }
            }

            if let overview, !overview.isEmpty {
                ExpandableTextBox(text: overview)
            }

            if !genres.isEmpty {
                HStack(spacing: 8) {
                    ForEach(genres) { genre in
                        Text(genre.name)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                }
            }

            if media.mediaType == .tv, let seasons = availableSeasons, !seasons.isEmpty {
                seasonSelection(seasons: seasons)
            }

            advancedOptionsSection

            requestSection
        }
        .padding(.horizontal, 80)
    }

    @ViewBuilder
    private var advancedOptionsSection: some View {
        if let details = serviceDetails, !didRequest {
            VStack(alignment: .leading, spacing: 12) {
                Text("catalog.request.advanced")
                    .font(.title3)
                    .fontWeight(.semibold)

                HStack(spacing: 16) {
                    profilePicker(details: details)
                    rootFolderPicker(details: details)
                }
            }
        }
    }

    private func profilePicker(details: SeerrServiceDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("catalog.request.qualityProfile")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(details.profiles) { profile in
                    Button {
                        selectedProfileID = profile.id
                    } label: {
                        if profile.id == selectedProfileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedProfileName(details: details))
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rootFolderPicker(details: SeerrServiceDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("catalog.request.rootFolder")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(details.rootFolders) { folder in
                    Button {
                        selectedRootFolder = folder.path
                    } label: {
                        if folder.path == selectedRootFolder {
                            Label(folder.path, systemImage: "checkmark")
                        } else {
                            Text(folder.path)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedRootFolder ?? String(localized: "catalog.request.rootFolder.default", defaultValue: "Default"))
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func selectedProfileName(details: SeerrServiceDetails) -> String {
        if let id = selectedProfileID,
           let profile = details.profiles.first(where: { $0.id == id }) {
            return profile.name
        }
        return String(localized: "catalog.request.qualityProfile.default", defaultValue: "Default")
    }

    private func seasonSelection(seasons: [SeerrSeason]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("catalog.seasons.select")
                .font(.title3)
                .fontWeight(.semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(seasons) { season in
                        SeasonChip(
                            season: season,
                            isSelected: selectedSeasons.contains(season.seasonNumber),
                            isAvailable: isSeasonAvailable(season),
                            toggle: { toggleSeason(season) }
                        )
                    }
                }
                // Horizontal padding leaves room for the focus-scale grow
                // on the first and last chips — without it the leftmost
                // season gets its halo clipped by the scroll-view edge.
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if didRequest {
                Label("catalog.request.sent", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
                    .fontWeight(.medium)
            } else {
                Button {
                    Task { await submitRequest() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    } else {
                        Label(requestButtonTitle, systemImage: "tray.and.arrow.down")
                            .font(.body)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                }
                .disabled(isSubmitting || !canSubmit)
            }

            if let requestError {
                Text(requestError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var requestButtonTitle: LocalizedStringKey {
        switch media.mediaType {
        case .movie: "catalog.button.request"
        case .tv: "catalog.button.requestSeasons"
        case .person: "catalog.button.request"
        }
    }

    private var canSubmit: Bool {
        switch media.mediaType {
        case .movie: true
        case .tv: !selectedSeasons.isEmpty
        case .person: false
        }
    }

    // MARK: - Derived

    private var displayTitle: String {
        movieDetail?.title ?? tvDetail?.name ?? media.displayTitle
    }

    private var displayYear: String? {
        movieDetail?.displayYear ?? tvDetail?.displayYear ?? media.displayYear
    }

    private var overview: String? {
        movieDetail?.overview ?? tvDetail?.overview ?? media.overview
    }

    private var genres: [SeerrGenre] {
        movieDetail?.genres ?? tvDetail?.genres ?? []
    }

    private var backdropPath: String? {
        movieDetail?.backdropPath ?? tvDetail?.backdropPath ?? media.backdropPath
    }

    private var mediaStatus: SeerrMediaStatus? {
        movieDetail?.mediaInfo?.status ?? tvDetail?.mediaInfo?.status ?? media.mediaInfo?.status
    }

    private var availableSeasons: [SeerrSeason]? {
        tvDetail?.seasons?.filter { $0.seasonNumber > 0 }
    }

    private func isSeasonAvailable(_ season: SeerrSeason) -> Bool {
        guard let requests = tvDetail?.mediaInfo?.requests else { return false }
        let occupiedStatuses: Set<SeerrMediaStatus> = [.available, .processing, .pending]
        for request in requests {
            guard let seasons = request.seasons else { continue }
            for s in seasons where s.seasonNumber == season.seasonNumber {
                if let status = s.status, occupiedStatuses.contains(status) {
                    return true
                }
            }
        }
        return false
    }

    private func toggleSeason(_ season: SeerrSeason) {
        if isSeasonAvailable(season) { return }
        if selectedSeasons.contains(season.seasonNumber) {
            selectedSeasons.remove(season.seasonNumber)
        } else {
            selectedSeasons.insert(season.seasonNumber)
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            switch media.mediaType {
            case .movie:
                movieDetail = try await dependencies.seerrMediaService.movieDetail(tmdbID: media.id)
            case .tv:
                tvDetail = try await dependencies.seerrMediaService.tvDetail(tmdbID: media.id)
            case .person:
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Load service config in the background — best-effort. If it
        // fails (admin hasn't configured Radarr/Sonarr, user lacks
        // permission), we silently fall back to Seerr's server defaults.
        await loadServiceConfig()
    }

    private func loadServiceConfig() async {
        let config = dependencies.seerrServiceConfigService
        do {
            let servers: [SeerrServiceServer]
            switch media.mediaType {
            case .movie: servers = try await config.radarrServers()
            case .tv: servers = try await config.sonarrServers()
            case .person: return
            }
            guard let chosen = servers.first(where: { $0.isDefault == true }) ?? servers.first else {
                return
            }
            let details: SeerrServiceDetails
            switch media.mediaType {
            case .movie: details = try await config.radarrDetails(serverID: chosen.id)
            case .tv: details = try await config.sonarrDetails(serverID: chosen.id)
            case .person: return
            }
            serviceDetails = details
            selectedProfileID = chosen.activeProfileId ?? details.profiles.first?.id
            selectedRootFolder = chosen.activeDirectory ?? details.rootFolders.first?.path
        } catch {
            // Swallow — dropdowns simply won't appear and the request
            // will use Seerr's defaults.
        }
    }

    private func submitRequest() async {
        isSubmitting = true
        requestError = nil
        defer { isSubmitting = false }

        let seasons: [Int]? = media.mediaType == .tv ? Array(selectedSeasons) : nil

        do {
            _ = try await dependencies.seerrRequestService.createRequest(
                mediaType: media.mediaType,
                tmdbID: media.id,
                seasons: seasons,
                serverID: serviceDetails?.server.id,
                profileID: selectedProfileID,
                rootFolder: selectedRootFolder,
                languageProfileID: serviceDetails?.server.activeLanguageProfileId
            )
            didRequest = true
        } catch {
            requestError = error.localizedDescription
        }
    }
}

private struct SeasonChip: View {
    let season: SeerrSeason
    let isSelected: Bool
    let isAvailable: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                if isAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                Text(seasonTitle)
                    .font(.body)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(background, in: Capsule())
        }
        .disabled(isAvailable)
    }

    private var seasonTitle: String {
        let label = String(localized: "catalog.season", defaultValue: "Season")
        return "\(label) \(season.seasonNumber)"
    }

    private var background: some ShapeStyle {
        if isAvailable { return AnyShapeStyle(.green.opacity(0.2)) }
        if isSelected { return AnyShapeStyle(.tint.opacity(0.35)) }
        return AnyShapeStyle(.white.opacity(0.1))
    }
}
