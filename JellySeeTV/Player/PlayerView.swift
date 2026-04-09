import SwiftUI

/// Temporary stub -- will be rebuilt with custom FFmpeg engine
struct PlayerView: View {
    let item: JellyfinItem
    let startFromBeginning: Bool
    let playbackService: JellyfinPlaybackServiceProtocol
    let userID: String
    var cachedPlaybackInfo: PlaybackInfoResponse?
    let onDismiss: () -> Void

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, cachedPlaybackInfo: PlaybackInfoResponse? = nil, onDismiss: @escaping () -> Void) {
        self.item = item
        self.startFromBeginning = startFromBeginning
        self.playbackService = playbackService
        self.userID = userID
        self.cachedPlaybackInfo = cachedPlaybackInfo
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Custom player engine in progress...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Button { onDismiss() } label: {
                    Text("home.retry")
                }
            }
        }
        .onExitCommand { onDismiss() }
    }
}
