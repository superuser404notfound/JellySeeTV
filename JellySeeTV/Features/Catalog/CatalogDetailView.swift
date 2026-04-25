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

    /// Currently-viewed season inside the season detail block — tab
    /// selection is independent of the request set so the user can
    /// browse a season's episodes without committing to request it.
    @State private var viewedSeasonNumber: Int?
    /// Per-season episode cache. Populated lazily as the user moves
    /// between tabs; once a season is fetched we keep it for the
    /// lifetime of the detail view.
    @State private var seasonEpisodes: [Int: [SeerrEpisode]] = [:]
    /// Per-season "loading episodes" markers — drives the spinner
    /// shown inside the episode strip while a fetch is in flight.
    @State private var loadingSeasons: Set<Int> = []

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
        VStack(alignment: .leading, spacing: 16) {
            Text("catalog.seasons.select")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(seasons) { season in
                            CatalogSeasonTab(
                                season: season,
                                isViewed: viewedSeasonNumber == season.seasonNumber,
                                isSelectedForRequest: selectedSeasons.contains(season.seasonNumber),
                                isAvailable: isSeasonAvailable(season),
                                action: { selectSeasonForViewing(season) }
                            )
                            .id(season.seasonNumber)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewedSeasonNumber) { _, newValue in
                    guard let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }

            // Per-season + select-all actions live below the tab row,
            // left-aligned. Keeping them out of the tab-row header
            // means the user can scan tabs without two competing
            // focus targets in the same horizontal slice.
            seasonActionsRow(seasons: seasons)

            if let viewed = viewedSeasonNumber,
               let season = seasons.first(where: { $0.seasonNumber == viewed }) {
                seasonDetailBlock(season: season)
            }
        }
    }

    @ViewBuilder
    private func seasonActionsRow(seasons: [SeerrSeason]) -> some View {
        let viewedSeason: SeerrSeason? = viewedSeasonNumber.flatMap { n in
            seasons.first(where: { $0.seasonNumber == n })
        }
        HStack(spacing: 12) {
            if let season = viewedSeason, !isSeasonAvailable(season) {
                let isSelected = selectedSeasons.contains(season.seasonNumber)
                Button {
                    toggleSeason(season)
                } label: {
                    Label(
                        isSelected
                            ? "catalog.seasons.removeFromRequest"
                            : "catalog.seasons.addToRequest",
                        systemImage: isSelected ? "checkmark.circle.fill" : "plus.circle"
                    )
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(SeasonChipButtonStyle())
            } else if let season = viewedSeason, isSeasonAvailable(season) {
                Label("catalog.seasons.alreadyAvailable", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            if hasSelectableSeasons(in: seasons) {
                Button {
                    toggleAllSeasons(seasons)
                } label: {
                    Label(
                        allSelectableSeasonsSelected(in: seasons)
                            ? "catalog.seasons.deselectAll"
                            : "catalog.seasons.selectAll",
                        systemImage: allSelectableSeasonsSelected(in: seasons)
                            ? "minus.circle"
                            : "plus.circle"
                    )
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(SeasonChipButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func seasonDetailBlock(season: SeerrSeason) -> some View {
        let n = season.seasonNumber
        let episodes = seasonEpisodes[n]

        VStack(alignment: .leading, spacing: 12) {
            // Season heading only — the per-season Add / Already
            // Available action moved up next to the tab row so it
            // sits in the same focus column as Select All.
            Text(seasonHeading(season: season))
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)

            if let overview = season.overview, !overview.isEmpty {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            }

            if loadingSeasons.contains(n) && (episodes?.isEmpty ?? true) {
                HStack {
                    ProgressView()
                    Spacer()
                }
                .frame(height: 220)
                .padding(.horizontal, 20)
            } else if let episodes, !episodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 24) {
                        ForEach(episodes) { ep in
                            FocusableCard(action: {}) { focused in
                                SeerrEpisodeCard(episode: ep, isFocused: focused)
                            }
                            .id("\(n)-\(ep.episodeNumber)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            } else if !loadingSeasons.contains(n) {
                Text("catalog.seasons.noEpisodes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 4)
    }

    private func seasonHeading(season: SeerrSeason) -> String {
        let label = String(localized: "catalog.season", defaultValue: "Season")
        if let name = season.name, !name.isEmpty, name != "\(label) \(season.seasonNumber)" {
            return "\(label) \(season.seasonNumber) · \(name)"
        }
        return "\(label) \(season.seasonNumber)"
    }

    private func selectSeasonForViewing(_ season: SeerrSeason) {
        let n = season.seasonNumber
        viewedSeasonNumber = n
        guard seasonEpisodes[n] == nil, !loadingSeasons.contains(n) else { return }
        Task { await loadSeasonEpisodes(seasonNumber: n) }
    }

    private func loadSeasonEpisodes(seasonNumber: Int) async {
        guard let tvID = tvDetail?.id else { return }
        loadingSeasons.insert(seasonNumber)
        defer { loadingSeasons.remove(seasonNumber) }
        do {
            let detail = try await dependencies.seerrMediaService.tvSeasonDetail(
                tmdbID: tvID,
                seasonNumber: seasonNumber
            )
            seasonEpisodes[seasonNumber] = detail.episodes ?? []
        } catch {
            // Best-effort — leave the cache empty so the "no episodes"
            // copy renders. Surfacing a banner here would compete with
            // the request-error label for screen real estate.
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
                let detail = try await dependencies.seerrMediaService.tvDetail(tmdbID: media.id)
                tvDetail = detail
                // Default the tab focus to the lowest-numbered real
                // season (skip specials/season 0). The episode block
                // below the tabs needs *some* season selected to have
                // anything to render — picking one synchronously here
                // means the user sees content the moment loading ends
                // instead of an empty space until they tap a tab.
                if let first = detail.seasons?
                    .filter({ $0.seasonNumber > 0 })
                    .sorted(by: { $0.seasonNumber < $1.seasonNumber })
                    .first {
                    viewedSeasonNumber = first.seasonNumber
                    Task { await loadSeasonEpisodes(seasonNumber: first.seasonNumber) }
                }
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

/// Season tab used inside the season selection block. The tab is
/// always selectable for *viewing* — even seasons that are already
/// available get tabs so the user can preview their episodes — but
/// the request action is gated separately inside the detail block.
private struct CatalogSeasonTab: View {
    let season: SeerrSeason
    let isViewed: Bool
    let isSelectedForRequest: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isSelectedForRequest {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                Text(seasonTitle)
                    .font(.body)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(background, in: Capsule())
        }
        .buttonStyle(SeasonChipButtonStyle())
    }

    private var seasonTitle: String {
        let label = String(localized: "catalog.season", defaultValue: "Season")
        return "\(label) \(season.seasonNumber)"
    }

    private var background: some ShapeStyle {
        if isViewed { return AnyShapeStyle(.tint.opacity(0.35)) }
        if isAvailable { return AnyShapeStyle(.green.opacity(0.18)) }
        if isSelectedForRequest { return AnyShapeStyle(.tint.opacity(0.18)) }
        return AnyShapeStyle(.white.opacity(0.08))
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
