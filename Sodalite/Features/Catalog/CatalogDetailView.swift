import SwiftUI

struct CatalogDetailView: View {
    let media: SeerrMedia
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    @State private var movieDetail: SeerrMovieDetail?
    @State private var tvDetail: SeerrTVDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var selectedSeasons: Set<Int> = []
    @State private var isSubmitting = false
    @State private var didRequest = false
    @State private var requestError: String?
    @State private var showCancelRequestConfirm = false
    @State private var isCancellingRequest = false

    /// Currently-viewed season; independent of the request set so the user can browse episodes without requesting.
    @State private var viewedSeasonNumber: Int?
    /// Per-season episode cache, lazily populated and kept for the view's lifetime.
    @State private var seasonEpisodes: [Int: [SeerrEpisode]] = [:]
    /// Per-season in-flight markers driving the episode-strip spinner.
    @State private var loadingSeasons: Set<Int> = []

    /// Jellyfin ground-truth reconcile of Seerr's cached availability. Seerr's mediaInfo.status stays "available" after a Radarr/Sonarr deletion until its ~6h availability-sync runs; Sodalite is the Jellyfin client, so it cross-checks the library directly and overrides stale "available" with .deleted. .unknown = trust Seerr (no Jellyfin user, lookup failed, or Seerr never claimed availability).
    @State private var titlePresence: JellyfinPresence = .unknown
    /// Per-season episode-file presence in Jellyfin (seasonNumber -> hasFiles); nil until the reconcile runs for a present series. A Seerr-available season absent here (or false) was deleted server-side.
    @State private var jellyfinSeasonHasFiles: [Int: Bool]?

    /// Recommendations (falling back to similar), loaded in parallel with the detail so the screen paints first.
    @State private var recommendations: [SeerrMedia] = []
    /// Rotten Tomatoes critics score, best-effort from Seerr's ratings endpoint; nil on older server / no RT data.
    @State private var rtCriticsScore: Int?
    @State private var navigateToMedia: SeerrMedia?
    @State private var selectedCastMember: CastMember?
    /// TMDB collection this movie belongs to; nil for standalone movies and for every series (Sodalite#52).
    @State private var navigateToCollection: SeerrCollectionRef?

    // Advanced request options from /service/radarr|sonarr; nil = omit field, falls back to Seerr's server default.
    @State private var serviceDetails: SeerrServiceDetails?
    @State private var selectedProfileID: Int?
    @State private var selectedRootFolder: String?
    /// Sonarr/Radarr tag ids; sent as nil when empty so older Jellyseerr builds that don't know the field still accept the body.
    @State private var selectedTagIDs: Set<Int> = []

    /// Mandatory request-options sheet (quality profile, root folder, tags + final confirm).
    @State private var showRequestOptions = false

    /// First-screen focus. Seeded to `.request` once loaded so no focus lands below the fold and triggers an on-open auto-scroll (old tab-bar-stuck-hidden bug). Request with no seasons picked moves focus to `.seasons` to scroll the picker into view.
    @FocusState private var focusedField: DetailFocus?
    /// Whole-page scroll proxy, iOS only (see PageScrollProxyCapture); nil on tvOS, where the focus engine scrolls.
    @State private var pageScrollProxy: ScrollViewProxy?
    private static let seasonSectionAnchor = "catalogSeasonSection"
    /// Overview box below the fold holds focus: Withdraw request leaves the focus engine for that
    /// time so an up-move can only land on the request button (Sodalite#53 follow-up).
    @State private var overviewHasFocus = false
    private enum DetailFocus: Hashable { case request, seasons }

    /// Result of the Jellyfin library cross-check. .unknown degrades to trusting Seerr; never a false .absent.
    private enum JellyfinPresence: Equatable { case unknown, present, absent }

    private var metrics: LayoutMetrics { LayoutMetrics.current(hSizeClass) }
    private var isPhonePortrait: Bool {
        #if os(iOS)
        hSizeClass == .compact && vSizeClass != .compact
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            DetailBackdrop(
                imageURL: SeerrImageURL.backdrop(path: backdropPath),
                posterFallbackURL: SeerrImageURL.poster(path: posterPath, size: .w780)
            )
                .id(backdropPath ?? "empty")
                .ignoresSafeArea()

            content
        }
        .ignoresSafeArea(when: !isPhonePortrait)
        .hidesToolbarBackground()
        .hidesShellTabBar()
        .navigationDestination(item: $navigateToMedia) { media in
            CatalogDetailView(media: media)
                .detailCoverPush()
        }
        .navigationDestination(item: $selectedCastMember) { member in
            PersonDetailView(personID: member.personID, personName: member.name)
                .detailCoverPush()
        }
        .navigationDestination(item: $navigateToCollection) { collection in
            // Hand over the Radarr options this screen already resolved: re-deriving them there is two more round
            // trips against a live Radarr, and the request button is the first focused element on that page, so its
            // sheet regularly opened before they landed and silently offered no options at all.
            CatalogCollectionView(
                collection: collection,
                serviceDetails: serviceDetails,
                profileID: selectedProfileID,
                rootFolder: selectedRootFolder
            )
                .detailCoverPush()
        }
        .sheet(isPresented: $showRequestOptions) {
            requestOptionsSheet
        }
        .onChange(of: isLoading) { _, loading in
            // Focus the action button so nothing below the fold auto-scrolls; defer dodges the focus-commit race (as MovieDetailView).
            if loading == false {
                deferOnMain(by: 0.1) { focusedField = .request }
            }
        }
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
            // Same shape as MovieDetailView: hero + bottom-aligned primary block fill screen one, rest scrolls below the fold; default focus stays in the visible block so opening never auto-scrolls (left the tab bar stuck hidden on mid-scroll back-out).
            DetailContentOverlay(
                heroImageURL: SeerrImageURL.backdrop(path: backdropPath),
                heroPosterURL: SeerrImageURL.poster(path: posterPath, size: .w780),
                hero: {
                heroTitle
            }, primary: {
                primaryBlock
            }) {
                trailingBody
            }
            .modifier(PageScrollProxyCapture(proxy: $pageScrollProxy))
        }
    }

    private func errorState(message: String) -> some View {
        // tvOS Menu pops the nav level only with something focusable; a text-only error screen would exit the app instead. Retry/Back buttons claim focus and give a recovery path.
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: hSizeClass == .compact ? 32 : 40))
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
                .buttonStyle(SettingsTileButtonStyle())
                Button {
                    dismiss()
                } label: {
                    Text("common.back")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(SettingsTileButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .screenContentInset()
    }

    // MARK: - Hero + primary block (first screen)

    @ViewBuilder
    private var heroTitle: some View {
        if isPhonePortrait {
            // On the narrow phone the year + status badge would steal the title's line and squeeze it
            // into a sliver that hard-wraps and truncates. Give the title the full width and drop the
            // year/badge onto their own row beneath it.
            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                heroTitleMeta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(displayTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                heroTitleMeta
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No extra horizontal padding: DetailContentOverlay's hero slot already insets by 50, lining up with the bubble and request button.
    }

    @ViewBuilder
    private var heroTitleMeta: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let year = displayYear {
                Text(year)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let status = mediaStatus, status != .unknown {
                SeerrStatusBadge(status: status)
            }
        }
    }

    private var primaryBlock: some View {
        VStack(alignment: .leading, spacing: 24) {
            metadataBubble
            requestActionRow
        }
        .padding(.horizontal, metrics.rowInset)
    }

    /// Metadata in a frosted bubble (matching Home detail views); left edge at the primary padding (50), aligned with hero title and request button.
    private var metadataBubble: some View {
        VStack(alignment: .leading, spacing: 12) {
            SeerrMetadataRow(
                rating: metadataRating,
                runtimeMinutes: metadataRuntime,
                year: nil,
                certification: metadataCertification,
                rtCriticsScore: rtCriticsScore
            )
            if !genres.isEmpty {
                Text(genres.map(\.name).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isPhonePortrait ? 16 : 30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private var requestActionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if didRequest {
                // Post-request CTA: nothing else focusable, so give a back-to-catalog action (else tvOS Menu exits the app).
                GlassActionButton(
                    title: "catalog.request.sent",
                    systemImage: "checkmark.circle.fill",
                    action: { dismiss() }
                )
                .focused($focusedField, equals: .request)
            } else if media.mediaType == .movie || media.mediaType == .tv {
                // Side by side wherever there is width (tvOS, iPad, phone landscape), matching the movie and series
                // detail rows; only the narrow phone portrait stacks them full width.
                if isPhonePortrait {
                    VStack(spacing: 12) { requestButtons }
                } else {
                    HStack(spacing: 16) { requestButtons }
                }

                if let requestError {
                    Text(requestError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog(
            "catalog.request.cancel.confirm.title",
            isPresented: $showCancelRequestConfirm,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await cancelOpenRequests() }
            } label: {
                Text("catalog.request.cancel.confirm.action")
            }
            Button(role: .cancel) { } label: {
                Text("common.cancel")
            }
        } message: {
            Text("catalog.request.cancel.confirm.message")
        }
    }

    @ViewBuilder
    private var requestButtons: some View {
        GlassActionButton(
            title: requestButtonTitle,
            systemImage: "tray.and.arrow.down",
            isProminent: true,
            isLoading: isSubmitting,
            action: { requestButtonTapped() }
        )
        .focused($focusedField, equals: .request)
        .disabled(isSubmitting)
        .frame(maxWidth: isPhonePortrait ? .infinity : nil)

        // Only offered while a request is actually open. Jellyseerr never revisits a request once it stops moving (its availability sync looks at available titles only), so a title pulled out of Sonarr elsewhere keeps reporting a pipeline state with no way to clear it from here.
        if !openRequests.isEmpty {
            GlassActionButton(
                title: "catalog.request.cancel",
                systemImage: "xmark.circle",
                isDestructive: true,
                isLoading: isCancellingRequest,
                action: { showCancelRequestConfirm = true }
            )
            .frame(maxWidth: isPhonePortrait ? .infinity : nil)
            .focusSuppressed(overviewHasFocus)
        }
    }

    /// Open requests on the currently loaded detail; drives both the cancel action's visibility and what it deletes.
    private var openRequests: [SeerrRequest] {
        let info = movieDetail?.mediaInfo ?? tvDetail?.mediaInfo
        return (info?.requests ?? []).filter(\.isOpen)
    }

    /// Deletes every open request for this title, then refreshes so the chips drop their pipeline state.
    /// Jellyseerr rejects this with 403 for a user who may not touch the request; that message is surfaced rather than swallowed, since the row stays visible and the user would otherwise retry forever.
    private func cancelOpenRequests() async {
        isCancellingRequest = true
        defer { isCancellingRequest = false }
        requestError = nil
        do {
            for request in openRequests {
                try await dependencies.seerrRequestService.deleteRequest(requestID: request.id)
            }
            // My Requests / the admin queue hold their rows until told; without this the removed request sits in the list until an app restart.
            NotificationCenter.default.post(name: .seerrRequestsDidChange, object: nil)
            await refreshDetailAfterRequest()
        } catch {
            requestError = ErrorText.user(for: error)
        }
    }

    /// Series with no seasons picked: bring the season picker into view; else present the options sheet.
    ///
    /// tvOS gets there by moving focus, which makes the focus engine scroll. iOS has no focus engine,
    /// so that write is a no-op and the tap did nothing at all: it scrolls the page itself instead.
    private func requestButtonTapped() {
        guard media.mediaType == .tv, selectedSeasons.isEmpty else {
            showRequestOptions = true
            return
        }
        focusedField = .seasons
        if let pageScrollProxy {
            withAnimation(.easeInOut(duration: 0.4)) {
                pageScrollProxy.scrollTo(Self.seasonSectionAnchor, anchor: .top)
            }
        }
    }

    // MARK: - Request options sheet

    // No ScrollView wrapper: a ScrollView root under-reports its height to a tvOS sheet, so the card is sized too short and the focused confirm button's halo (SettingsTileButtonStyle scale+shadow+stroke) gets clipped at the bottom edge. The content (title + a few advanced rows + button) always fits, so the sheet hugs the real VStack height instead.
    private var requestOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(displayTitle)
                .font(.title2)
                .fontWeight(.bold)

            // Empty for users without service options; confirm still submits with server defaults.
            advancedOptionsSection

            Button {
                Task {
                    await submitRequest()
                    if didRequest { showRequestOptions = false }
                }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Label(requestButtonTitle, systemImage: "tray.and.arrow.down")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .buttonStyle(SettingsTileButtonStyle())
            .disabled(isSubmitting || !canSubmit)

            if let requestError {
                Text(requestError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(48)
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trailing (scrolls below the fold)

    private var trailingBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let overview, !overview.isEmpty {
                // Up out of the box lands on the row's last button, here Withdraw request, unless it
                // is corrected: the engine resolves it from the box's centre (Sodalite#53).
                ExpandableTextBox(
                    text: overview,
                    onFocusMovedUp: { focusedField = .request },
                    onFocusChanged: { overviewHasFocus = $0 }
                )
            }

            // The stub rides along on `/movie/{id}`, so the entry point costs no extra request; the parts are fetched only once the collection is opened.
            if let collection = movieDetail?.collection {
                SeerrCollectionBanner(collection: collection) {
                    navigateToCollection = collection
                }
            }

            if media.mediaType == .tv, let seasons = availableSeasons, !seasons.isEmpty {
                seasonSelection(seasons: seasons)
                    .id(Self.seasonSectionAnchor)
            }

            if !castMembers.isEmpty {
                MediaCastRow(members: castMembers) { member in
                    if member.personID != nil {
                        selectedCastMember = member
                    }
                }
                .padding(.horizontal, -metrics.rowInset)
            }

            if !regionWatchProviders.isEmpty {
                SeerrWatchProvidersRow(providers: regionWatchProviders)
                    .padding(.horizontal, -metrics.rowInset)
            }

            if !recommendations.isEmpty {
                SeerrHorizontalMediaRow(
                    title: "detail.moreLikeThis",
                    items: recommendations,
                    onItemSelected: { navigateToMedia = $0 }
                )
                .padding(.horizontal, -metrics.rowInset)
            }
        }
        .padding(.horizontal, metrics.rowInset)
    }

    @ViewBuilder
    private var advancedOptionsSection: some View {
        if let details = serviceDetails, !didRequest {
            SeerrRequestOptionsForm(
                details: details,
                selectedProfileID: $selectedProfileID,
                selectedRootFolder: $selectedRootFolder,
                selectedTagIDs: $selectedTagIDs
            )
        }
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
                                availabilityStatus: seasonStatus(season),
                                action: { selectSeasonForViewing(season) }
                            )
                            .id(season.seasonNumber)
                            // Focus anchor for requestButtonTapped's no-seasons-picked path.
                            .applyIf(season.seasonNumber == seasons.first?.seasonNumber) {
                                $0.focused($focusedField, equals: .seasons)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .focusSectionCompat()
                .onChange(of: viewedSeasonNumber) { _, newValue in
                    guard let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }

            // Per-season + select-all actions below the tab row so tabs aren't sharing a horizontal focus slice with competing targets.
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
        // Wrapping row, not an HStack: on a phone in portrait the three chips exceed the line width and
        // an HStack resolves that by wrapping each label's text internally (three ragged multi-line columns).
        // FlowLayout keeps every chip on one text line and moves the overflow chip to a second row instead.
        FlowLayout(alignment: .leading, spacing: 12) {
            if let season = viewedSeason {
                // Status is informational and never blocks: show the pipeline state (if any) as a label, then always offer add/remove so a deleted-but-stale-available season stays re-requestable.
                if let status = seasonStatus(season) {
                    Label(
                        seasonStatusLabel(status),
                        systemImage: status.systemImage
                    )
                    .font(.caption)
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func seasonDetailBlock(season: SeerrSeason) -> some View {
        let n = season.seasonNumber
        let episodes = seasonEpisodes[n]

        VStack(alignment: .leading, spacing: 12) {
            // Heading only; the per-season Add / Already-Available action moved up by the tab row to share a focus column with Select All.
            Text(seasonHeading(season: season))
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)

            // Same box as the series overview above: a season synopsis is regularly longer than the
            // three lines a plain Text could show, so it gets the identical focusable / tappable
            // full-text overlay instead of a truncation the user cannot open.
            if let overview = season.overview, !overview.isEmpty {
                ExpandableTextBox(text: overview)
                    .padding(.horizontal, 4)
            }

            if loadingSeasons.contains(n) && (episodes?.isEmpty ?? true) {
                HStack {
                    ProgressView()
                    Spacer()
                }
                // Reserve the height the card row will actually take, so the swap from spinner to cards doesn't jump.
                .frame(height: SeerrEpisodeCard.size(
                    compact: hSizeClass == .compact,
                    cardScale: dependencies.appearancePreferences.cardScale
                ).height + (hSizeClass == .compact ? 58 : 40))
                .padding(.horizontal, 20)
            } else if let episodes, !episodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: hSizeClass == .compact ? metrics.itemSpacing : 24) {
                        ForEach(episodes) { ep in
                            FocusableCard(action: {}) { focused in
                                SeerrEpisodeCard(episode: ep, isFocused: focused)
                            }
                            .id("\(n)-\(ep.episodeNumber)")
                        }
                    }
                    .padding(.horizontal, 20)
                    // Room for the focused card's scale (1.04) + drop shadow (radius 14, y 6) the ScrollView would otherwise clip.
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .focusSectionCompat()
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
            // Best-effort: leave the cache empty so "no episodes" renders; a banner would compete with the request-error label.
        }
    }

    private func selectableSeasons(in seasons: [SeerrSeason]) -> [SeerrSeason] {
        // Status never gates a request: a season deleted in Radarr/Sonarr (server reports it stale-available) must stay re-requestable, so every real season is selectable and status is display-only.
        seasons
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


    private var requestButtonTitle: LocalizedStringKey {
        switch media.mediaType {
        case .movie: "catalog.button.request"
        case .tv: "catalog.button.requestSeasons"
        case .person, .unknown: "catalog.button.request"
        }
    }

    private var canSubmit: Bool {
        switch media.mediaType {
        case .movie: true
        case .tv: !selectedSeasons.isEmpty
        case .person, .unknown: false
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

    /// Same fetched-first order as `backdropPath`. Reading it off `media` alone left the hero blank for the whole visit when the screen was entered from My Requests, which navigates with a bare tmdb-id stub: the phone-portrait hero shows the poster ONLY, so the stub's nil poster was the entire hero.
    private var posterPath: String? {
        movieDetail?.posterPath ?? tvDetail?.posterPath ?? media.posterPath
    }

    private var mediaStatus: SeerrMediaStatus? {
        let seerr = movieDetail?.mediaInfo?.status ?? tvDetail?.mediaInfo?.status ?? media.mediaInfo?.status
        // Jellyfin ground truth: the whole title is gone, so override Seerr's stale "available" badge with .deleted.
        if (seerr == .available || seerr == .partiallyAvailable), titlePresence == .absent {
            return .deleted
        }
        return seerr
    }

    private var availableSeasons: [SeerrSeason]? {
        tvDetail?.seasons?.filter { $0.seasonNumber > 0 }
    }

    private var deviceRegion: String {
        Locale.current.region?.identifier ?? "US"
    }

    private var metadataRating: Double? {
        movieDetail?.voteAverage ?? tvDetail?.voteAverage ?? media.voteAverage
    }

    /// Runtime in minutes. Movies only; TV omits it in SP1.
    private var metadataRuntime: Int? {
        movieDetail?.runtime
    }

    private var metadataCertification: String? {
        movieDetail?.certification(region: deviceRegion)
            ?? tvDetail?.certification(region: deviceRegion)
    }

    private var castMembers: [CastMember] {
        let cast = movieDetail?.credits?.cast ?? tvDetail?.credits?.cast ?? []
        return cast.prefix(15).map { member in
            CastMember(
                id: "\(member.id)",
                name: member.name,
                role: member.character,
                imageURL: SeerrImageURL.profile(
                    path: member.profilePath,
                    size: .covering(metrics.castImageWidth)
                ),
                personID: member.id,
                jellyfinPersonID: nil
            )
        }
    }

    /// Flatrate providers for the device region, falling back to US then the first region; empty when none.
    private var regionWatchProviders: [SeerrWatchProvider] {
        let regions = movieDetail?.watchProviders ?? tvDetail?.watchProviders ?? []
        guard !regions.isEmpty else { return [] }
        let pick = regions.first { $0.iso31661 == deviceRegion }
            ?? regions.first { $0.iso31661 == "US" }
            ?? regions.first
        return pick?.flatrate ?? []
    }

    /// Informational status for the season, or nil if untracked. Never gates requesting (status is display-only); a deleted/declined season must still be re-requestable.
    /// Layers Seerr's cached status with the Jellyfin ground-truth override: a stale "available" is downgraded to .deleted when the season's episode files are actually gone from the library.
    private func seasonStatus(_ season: SeerrSeason) -> SeerrMediaStatus? {
        let seerr = seerrSeasonStatus(season.seasonNumber)
        // Jellyfin ground truth: override Seerr's stale available/partially-available with .deleted when the show is gone entirely (titlePresence absent) or this specific season has no episode files, so the user sees it's gone (and can re-request).
        if seerr == .available || seerr == .partiallyAvailable {
            if titlePresence == .absent { return .deleted }
            if let hasFiles = jellyfinSeasonHasFiles, hasFiles[season.seasonNumber] != true {
                return .deleted
            }
        }
        return seerr
    }

    private func seerrSeasonStatus(_ n: Int) -> SeerrMediaStatus? {
        SeerrSeasonStatusResolver.status(seasonNumber: n, mediaInfo: tvDetail?.mediaInfo)
    }

    private func seasonStatusLabel(_ status: SeerrMediaStatus) -> LocalizedStringKey {
        switch status {
        case .available: return "catalog.seasons.alreadyAvailable"
        // Same wording as the title badge: `.processing` is Jellyseerr's "in the pipeline", and the client cannot tell an active download from a request Sonarr has long stopped acting on, so it must not claim one.
        case .processing: return "catalog.status.processing"
        case .pending: return "catalog.seasons.pendingApproval"
        case .partiallyAvailable: return "catalog.status.partiallyAvailable"
        case .deleted: return "catalog.status.removed"
        case .unknown: return "catalog.status.unknown"
        }
    }

    private func toggleSeason(_ season: SeerrSeason) {
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

        // Fire-and-forget (not async let): detail render must not block on best-effort Radarr/Sonarr config that only feeds optional dropdowns.
        Task { await loadServiceConfig() }
        Task { await loadRecommendations() }
        Task { await loadRatings() }

        do {
            switch media.mediaType {
            case .movie:
                movieDetail = try await dependencies.seerrMediaService.movieDetail(tmdbID: media.id)
                // Background: reconcile Seerr's cached availability against the Jellyfin library; patches the badge after first paint, never blocks.
                Task { await reconcileAvailability() }
                return
            case .tv:
                let detail = try await dependencies.seerrMediaService.tvDetail(tmdbID: media.id)
                tvDetail = detail
                Task { await reconcileAvailability() }
                // Default to the lowest real season (skip specials/season 0) synchronously so the episode block has content the instant loading ends.
                let realSeasons = (detail.seasons ?? [])
                    .filter { $0.seasonNumber > 0 }
                    .map(\.seasonNumber)
                    .sorted()
                if let first = realSeasons.first {
                    viewedSeasonNumber = first
                    // Strictly lazy (one season up front). Fanning out one tvSeasonDetail per season fired 30+ parallel HTTP/2 streams at remote Jellyseerr, saturating the pool and starving TMDB artwork loads.
                    Task { await loadSeasonEpisodes(seasonNumber: first) }
                }
                return
            case .person, .unknown:
                return
            }
        } catch {
            errorMessage = ErrorText.user(for: error)
        }
    }

    /// Cross-checks Seerr's cached availability against the Jellyfin library (the playability ground truth). Runs only when Seerr claims available/partially-available; degrades to .unknown (trust Seerr) on any lookup failure, never a false "deleted". For series it also builds the per-season episode-file map so individually deleted seasons surface even when the show is otherwise present.
    private func reconcileAvailability() async {
        guard let userID = appState.activeUser?.id else { return }
        let seerrStatus = movieDetail?.mediaInfo?.status ?? tvDetail?.mediaInfo?.status
        guard seerrStatus == .available || seerrStatus == .partiallyAvailable else { return }

        let service = dependencies.jellyfinItemService
        switch media.mediaType {
        case .movie:
            do {
                let item = try await resolveLibraryItem(userID: userID, types: [.movie])
                guard let item else {
                    // Unresolvable, not proven gone: leave Seerr's own status standing.
                    titlePresence = .unknown
                    return
                }
                // Present only if the matched item carries a real media source; a shell with no file counts as gone.
                titlePresence = (item.mediaSources?.isEmpty == false) ? .present : .absent
            } catch {
                titlePresence = .unknown
            }
        case .tv:
            do {
                let series = try await resolveLibraryItem(userID: userID, types: [.series])
                guard let series else {
                    titlePresence = .unknown
                    return
                }
                titlePresence = .present
                // childCount rides on the seasons endpoint's ChildCount field (seasonListFields, and it has to be that exact field); a season Jellyfin lists with zero episode files, or doesn't list at all, was deleted.
                let seasons = try await service.getSeasons(seriesID: series.id, userID: userID).items
                var hasFiles: [Int: Bool] = [:]
                for season in seasons {
                    guard let n = season.indexNumber else { continue }
                    hasFiles[n] = (season.childCount ?? 0) > 0
                }
                jellyfinSeasonHasFiles = hasFiles
            } catch {
                titlePresence = .unknown
            }
        case .person, .unknown:
            break
        }
    }

    /// Jellyseerr's own `jellyfinMediaId` first: it is an exact link, written by the scan that decided this title is available. A 404 on it is real proof the item is gone, which no provider-id guess can give.
    /// Only when Seerr carries no link (Overseerr, or an unmatched title) does it fall back to the id-verified title search.
    private func resolveLibraryItem(userID: String, types: [ItemType]) async throws -> JellyfinItem? {
        let service = dependencies.jellyfinItemService
        let info = movieDetail?.mediaInfo ?? tvDetail?.mediaInfo
        if let linkedID = info?.jellyfinMediaId, !linkedID.isEmpty {
            do {
                return try await service.getItemDetail(userID: userID, itemID: linkedID)
            } catch let error as APIError where error.isNotFound {
                titlePresence = .absent
                return nil
            }
        }
        return try await service.findByProviderIDs(
            userID: userID,
            tmdbID: media.id,
            tvdbID: tvDetail?.externalIds?.tvdbId,
            imdbID: tvDetail?.externalIds?.imdbId ?? movieDetail?.externalIds?.imdbId,
            includeItemTypes: types,
            searchTerm: tvDetail?.name ?? movieDetail?.title ?? media.displayTitle
        )
    }

    private func loadRecommendations() async {
        let service = dependencies.seerrMediaService
        do {
            // Titles the server already has are dropped: this row is the catalog, and what is on the
            // server belongs on its own detail page, not behind a request button (Vincent, 2026-08-17).
            // The filter runs before the empty check, so a wall of owned recommendations falls through
            // to similar instead of leaving the row looking short for no reason.
            let recs = SeerrLibraryDedupe.droppingAvailable(
                try await service.recommendations(mediaType: media.mediaType, tmdbID: media.id)
            )
            if !recs.isEmpty {
                recommendations = recs
                return
            }
            recommendations = SeerrLibraryDedupe.droppingAvailable(
                try await service.similar(mediaType: media.mediaType, tmdbID: media.id)
            )
        } catch {
            // Best-effort: leave the row absent, no banner.
        }
    }

    private func loadRatings() async {
        // Nothing to draw, nothing to ask for (Sodalite#127).
        guard dependencies.appearancePreferences.showCriticRating else { return }
        // Best-effort: the ratings endpoint 404s on older servers or when no
        // RT data exists, leave the badge absent in that case.
        guard let rt = try? await dependencies.seerrMediaService.ratings(
            mediaType: media.mediaType, tmdbID: media.id
        ) else { return }
        if let score = rt.criticsScore { rtCriticsScore = score }
    }

    private func loadServiceConfig() async {
        do {
            guard let resolved = try await SeerrRequestDefaults.resolve(
                service: dependencies.seerrServiceConfigService,
                mediaType: media.mediaType
            ) else { return }
            serviceDetails = resolved.details
            selectedProfileID = resolved.profileID
            selectedRootFolder = resolved.rootFolder
        } catch {
            // Swallow, dropdowns simply won't appear and the request
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
                languageProfileID: serviceDetails?.server.activeLanguageProfileId,
                tags: selectedTagIDs.isEmpty ? nil : Array(selectedTagIDs)
            )
            didRequest = true
            // Nudge request lists (My Requests / admin queue) to refresh; they only reload-when-empty on section switch.
            NotificationCenter.default.post(name: .seerrRequestsDidChange, object: nil)
            // Refresh mediaInfo so chips/badges drop stale "not requested" state. NOT load(): that flips the full-screen loading state and re-runs config/recommendations.
            await refreshDetailAfterRequest()
        } catch {
            requestError = ErrorText.user(for: error)
        }
    }

    /// Light refresh after a successful request: replaces only the mediaInfo-carrying detail (badges/chips pick up pending state); tab selection and episode lists stay untouched.
    private func refreshDetailAfterRequest() async {
        do {
            switch media.mediaType {
            case .movie:
                movieDetail = try await dependencies.seerrMediaService.movieDetail(tmdbID: media.id)
            case .tv:
                tvDetail = try await dependencies.seerrMediaService.tvDetail(tmdbID: media.id)
            case .person, .unknown:
                break
            }
            // Re-reconcile so the Jellyfin presence verdict matches the refreshed mediaInfo; background so it doesn't extend the submit spinner, self-guards on Seerr still claiming availability.
            Task { await reconcileAvailability() }
        } catch {
            // Badges stay stale until the next open; not worth an alert.
        }
    }
}
