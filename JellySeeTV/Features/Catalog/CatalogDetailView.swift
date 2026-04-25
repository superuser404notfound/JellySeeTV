import SwiftUI

struct CatalogDetailView: View {
    let media: SeerrMedia
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var movieDetail: SeerrMovieDetail?
    @State private var tvDetail: SeerrTVDetail?
    @State private var trailer: TrailerSource?
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

    /// Presentation state for the picker sheets. SwiftUI's `Menu`
    /// hands focus off to a system-controlled overlay that the focus
    /// engine unwinds oddly on tvOS — during the ~1s close animation
    /// a Menu-button press escaped up the navigation stack and
    /// exited the app. `.fullScreenCover` is self-contained: the
    /// cover owns its focus environment, the Menu-button dismisses
    /// only the cover, and nothing leaks into the parent.
    @State private var isProfilePickerPresented = false
    @State private var isRootFolderPickerPresented = false

    var body: some View {
        ZStack {
            DetailBackdrop(imageURL: SeerrImageURL.backdrop(path: backdropPath))
                .id(backdropPath ?? "empty")

            content
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            errorState(message: errorMessage)
        } else {
            DetailContentOverlay {
                detailBody
            }
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

            // Trailer button — shown only when Jellyseerr's
            // relatedVideos has a YouTube trailer for this item.
            // The resolution happens in load(); this is purely a
            // binding.
            TrailerButton(trailer: trailer)

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

            Button {
                isProfilePickerPresented = true
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
            .buttonStyle(CatalogPickerButtonStyle())
            .fullScreenCover(isPresented: $isProfilePickerPresented) {
                CatalogPickerSheet(
                    title: String(localized: "catalog.request.qualityProfile", defaultValue: "Quality profile"),
                    options: details.profiles.map { .init(id: "\($0.id)", label: $0.name) },
                    selectedID: selectedProfileID.map(String.init),
                    onSelect: { rawID in
                        if let id = Int(rawID) {
                            selectedProfileID = id
                        }
                        isProfilePickerPresented = false
                    },
                    onCancel: { isProfilePickerPresented = false }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rootFolderPicker(details: SeerrServiceDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("catalog.request.rootFolder")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isRootFolderPickerPresented = true
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
            .buttonStyle(CatalogPickerButtonStyle())
            .fullScreenCover(isPresented: $isRootFolderPickerPresented) {
                CatalogPickerSheet(
                    title: String(localized: "catalog.request.rootFolder", defaultValue: "Root folder"),
                    options: details.rootFolders.map { .init(id: $0.path, label: $0.path) },
                    selectedID: selectedRootFolder,
                    onSelect: { path in
                        selectedRootFolder = path
                        isRootFolderPickerPresented = false
                    },
                    onCancel: { isRootFolderPickerPresented = false }
                )
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

            // Select-all sits *below* the horizontal chip row rather
            // than as its last peer — for series with many seasons
            // the user would otherwise have to scroll all the way to
            // the right to reach it. Below-the-row keeps it always
            // one down-swipe away.
            if hasSelectableSeasons(in: seasons) {
                SelectAllChip(
                    isAllSelected: allSelectableSeasonsSelected(in: seasons),
                    toggle: { toggleAllSeasons(seasons) }
                )
                .padding(.leading, 20)
            }
        }
    }

    private func selectableSeasons(in seasons: [SeerrSeason]) -> [SeerrSeason] {
        seasons.filter { !isSeasonAvailable($0) }
    }

    private func hasSelectableSeasons(in seasons: [SeerrSeason]) -> Bool {
        !selectableSeasons(in: seasons).isEmpty
    }

    private func allSelectableSeasonsSelected(in seasons: [SeerrSeason]) -> Bool {
        let selectable = selectableSeasons(in: seasons)
        guard !selectable.isEmpty else { return false }
        return selectable.allSatisfy { selectedSeasons.contains($0.seasonNumber) }
    }

    private func toggleAllSeasons(_ seasons: [SeerrSeason]) {
        let selectable = selectableSeasons(in: seasons)
        if allSelectableSeasonsSelected(in: seasons) {
            for season in selectable {
                selectedSeasons.remove(season.seasonNumber)
            }
        } else {
            for season in selectable {
                selectedSeasons.insert(season.seasonNumber)
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

        await resolveTrailer()

        // Load service config in the background — best-effort. If it
        // fails (admin hasn't configured Radarr/Sonarr, user lacks
        // permission), we silently fall back to Seerr's server defaults.
        await loadServiceConfig()
    }

    /// Resolution chain: iTunes (native MP4) → YouTube → unavailable.
    /// iTunes is preferred because its previewUrl plays through
    /// AVPlayer with no external-app round-trip; YouTube remains
    /// the catch-all for items iTunes doesn't list (TV mostly).
    private func resolveTrailer() async {
        let videos: [SeerrVideo]?
        let releaseYear: Int?
        switch media.mediaType {
        case .movie:
            videos = movieDetail?.relatedVideos
            releaseYear = Int((movieDetail?.releaseDate ?? "").prefix(4))
        case .tv:
            videos = tvDetail?.relatedVideos
            releaseYear = Int((tvDetail?.firstAirDate ?? "").prefix(4))
        case .person:
            videos = nil
            releaseYear = nil
        }

        #if DEBUG
        print("[Trailer] seerr id=\(media.id) type=\(media.mediaType.rawValue) videoCount=\(videos?.count ?? -1) ytTrailers=\(videos?.filter { $0.isYouTube && $0.isTrailer }.count ?? 0)")
        #endif

        // 1. iTunes — native MP4. Only for movies; iTunes' TV
        //    storefront entries are by season and rarely carry a
        //    series-level trailer, so we'd just hit lookup misses.
        if media.mediaType == .movie,
           let previewURL = await ITunesTrailerLookup.lookup(
                title: displayTitle,
                year: releaseYear
           ) {
            trailer = .directVideo(url: previewURL, title: displayTitle)
            #if DEBUG
            print("[Trailer] resolved .directVideo \(previewURL)")
            #endif
            return
        }

        // 2. YouTube — covers TV and any movie iTunes didn't have.
        guard let videos else { trailer = .unavailable; return }
        if let t = videos.first(where: { $0.isTrailer && $0.isYouTube }),
           let y = YouTubeURL.from(key: t.key) {
            trailer = .youtube(
                videoKey: y.videoKey,
                watchURL: y.watchURL,
                title: t.name ?? displayTitle
            )
            return
        }
        if let any = videos.first(where: { $0.isYouTube }),
           let y = YouTubeURL.from(key: any.key) {
            trailer = .youtube(
                videoKey: y.videoKey,
                watchURL: y.watchURL,
                title: any.name ?? displayTitle
            )
            return
        }
        trailer = .unavailable
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
        // Without an explicit ButtonStyle, tvOS layers its own
        // default focus halo on top of our Capsule background —
        // the user sees two concentric outlines. Custom style
        // that does scale + accent stroke matches the rest of
        // the app's focus treatment instead.
        .buttonStyle(SeasonChipButtonStyle())
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

private struct SelectAllChip: View {
    let isAllSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: isAllSelected ? "xmark.circle" : "checkmark.circle")
                    .font(.caption)
                Text(isAllSelected ? "catalog.seasons.deselectAll" : "catalog.seasons.selectAll")
                    .font(.body)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(SeasonChipButtonStyle())
    }
}

private struct SeasonChipButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                Capsule()
                    .strokeBorder(.tint, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Picker Button Style

private struct CatalogPickerButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Picker Sheet

/// Full-screen picker for the profile / root-folder dropdowns.
/// `.fullScreenCover` gives the sheet its own focus environment —
/// the Menu-button dismisses only this modal, no chance of
/// propagating up to the navigation stack and accidentally
/// exiting the app (which is what happened with SwiftUI `Menu`
/// on tvOS during its close animation).
private struct CatalogPickerSheet: View {
    struct Option: Identifiable {
        let id: String
        let label: String
    }

    let title: String
    let options: [Option]
    let selectedID: String?
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var focusedID: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 32) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 60)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option.id)
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Spacer()
                                    if option.id == selectedID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 18)
                                .frame(maxWidth: .infinity)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(CatalogPickerButtonStyle())
                            .focused($focusedID, equals: option.id)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 60)
                }
            }
        }
        // Menu-button dismisses the sheet; tvOS would otherwise
        // eat the press against an empty focus environment.
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            // Focus the currently-selected option on appear, or the
            // first one if nothing's selected — so the back-press gap
            // never hits an empty focus.
            focusedID = selectedID ?? options.first?.id
        }
    }
}
