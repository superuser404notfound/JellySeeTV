import SwiftUI

/// Reusable trailer action across detail views. Resolves the best
/// available source on appear, then renders a button that:
///   - plays local trailers through AetherEngine (same player as
///     regular content), or
///   - hands YouTube trailers off to the external YouTube app with
///     a QR-code sheet as the fallback for when the OS can't open
///     the URL.
///
/// When no trailer is available for the item, the button renders
/// nothing — keeps the detail view's action row uncluttered.
struct TrailerButton: View {

    enum Source {
        case jellyfin(JellyfinItem)
        case seerr(tmdbID: Int, mediaType: SeerrMediaType, title: String?)
    }

    let source: Source

    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    @State private var resolved: TrailerSource?
    @State private var showPlayer = false
    @State private var showQR = false
    @State private var qrTarget: (url: URL, title: String?)?

    var body: some View {
        Group {
            switch resolved {
            case .local, .youtube:
                button
            case .unavailable, .none:
                EmptyView()
            }
        }
        .task(id: sourceID) {
            resolved = nil
            resolved = await resolve()
        }
        .overlay {
            if case .local(let trailerItem) = resolved,
               let userID = appState.activeUser?.id {
                PlayerLauncher(
                    isPresented: $showPlayer,
                    item: showPlayer ? trailerItem : nil,
                    startFromBeginning: true,
                    playbackService: dependencies.jellyfinPlaybackService,
                    userID: userID,
                    preferences: dependencies.playbackPreferences,
                    cachedPlaybackInfo: nil,
                    tintColor: dependencies.appearancePreferences.effectiveTint(
                        isSupporter: dependencies.storeKitService.isSupporter
                    )
                )
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showQR) {
            if let qrTarget {
                TrailerQRFallbackView(watchURL: qrTarget.url, title: qrTarget.title)
            }
        }
    }

    // MARK: - Button

    @ViewBuilder
    private var button: some View {
        GlassActionButton(
            title: "trailer.play",
            systemImage: "play.rectangle.fill"
        ) {
            Task { await handleTap() }
        }
    }

    // MARK: - Actions

    private func handleTap() async {
        switch resolved {
        case .local:
            showPlayer = true
        case .youtube(_, let url, let title):
            let target = YouTubeURL.parse(from: url.absoluteString)
                ?? YouTubeURL(videoKey: url.lastPathComponent)
            let outcome = await TrailerLauncher.open(target)
            if outcome == .fallbackToQR {
                qrTarget = (url, title)
                showQR = true
            }
        case .unavailable, .none:
            break
        }
    }

    // MARK: - Resolution

    private var sourceID: String {
        switch source {
        case .jellyfin(let item): "jf-\(item.id)"
        case .seerr(let tmdbID, let type, _): "seerr-\(type.rawValue)-\(tmdbID)"
        }
    }

    private func resolve() async -> TrailerSource {
        let service = TrailerService(
            libraryService: dependencies.jellyfinLibraryService,
            mediaService: dependencies.seerrMediaService
        )
        switch source {
        case .jellyfin(let item):
            return await service.resolveTrailer(for: item)
        case .seerr(let tmdbID, let mediaType, let title):
            return await service.resolveTrailer(
                forTMDBID: tmdbID,
                mediaType: mediaType,
                fallbackTitle: title
            )
        }
    }
}
