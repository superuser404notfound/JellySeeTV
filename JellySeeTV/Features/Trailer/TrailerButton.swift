import SwiftUI

/// Pure presentational button that renders a trailer action when
/// its owner has resolved a source, and hides itself otherwise.
/// Resolution happens in the enclosing view model — Detail /
/// Catalog view models call their TrailerService and publish into
/// an observable `trailer` property. Keeping the resolve out of
/// the view makes the state machine visible (a single @Observable
/// property) and means SwiftUI doesn't have to re-synchronize an
/// async `.task` against item refreshes.
struct TrailerButton: View {
    let trailer: TrailerSource?

    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    @State private var showPlayer = false
    @State private var showDirectVideo = false
    @State private var directVideoURL: URL?
    @State private var showQR = false
    @State private var qrTarget: (url: URL, title: String?)?

    var body: some View {
        Group {
            switch trailer {
            case .local, .directVideo, .youtube:
                button
            case .unavailable, .none:
                EmptyView()
            }
        }
        .overlay {
            if case .local(let trailerItem) = trailer,
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
        .fullScreenCover(isPresented: $showDirectVideo) {
            if let directVideoURL {
                DirectVideoPlayerView(url: directVideoURL)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showQR) {
            if let qrTarget {
                TrailerQRFallbackView(watchURL: qrTarget.url, title: qrTarget.title)
            }
        }
    }

    private var button: some View {
        GlassActionButton(
            title: "trailer.play",
            systemImage: "play.rectangle.fill"
        ) {
            Task { await handleTap() }
        }
    }

    private func handleTap() async {
        switch trailer {
        case .local:
            showPlayer = true
        case .directVideo(let url, _):
            directVideoURL = url
            showDirectVideo = true
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
}
