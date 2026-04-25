import SwiftUI

/// Pure presentational button. Source resolution lives in the
/// enclosing view model (DetailViewModel for Jellyfin items,
/// CatalogDetailView's @State for Seerr items). Two playback
/// surfaces, both in-app:
///
///   .local       → AetherEngine via PlayerLauncher (full quality
///                  Jellyfin pipeline)
///   .directVideo → AVPlayerViewController (iTunes preview MP4,
///                  native tvOS player)
struct TrailerButton: View {
    let trailer: TrailerSource?

    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    @State private var showLocalPlayer = false
    @State private var showDirectVideo = false

    var body: some View {
        Group {
            switch trailer {
            case .local, .directVideo:
                button
            case .unavailable, .none:
                EmptyView()
            }
        }
        .overlay {
            if case .local(let trailerItem) = trailer,
               let userID = appState.activeUser?.id {
                PlayerLauncher(
                    isPresented: $showLocalPlayer,
                    item: showLocalPlayer ? trailerItem : nil,
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
            if case .directVideo(let url, _) = trailer {
                DirectVideoPlayerView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    private var button: some View {
        GlassActionButton(
            title: "trailer.play",
            systemImage: "play.rectangle.fill"
        ) {
            handleTap()
        }
    }

    private func handleTap() {
        switch trailer {
        case .local:
            showLocalPlayer = true
        case .directVideo:
            showDirectVideo = true
        case .unavailable, .none:
            break
        }
    }
}
