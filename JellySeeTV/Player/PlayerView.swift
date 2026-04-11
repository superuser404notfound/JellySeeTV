import SwiftUI

struct PlayerView: View {
    @State private var viewModel: PlayerViewModel
    let onDismiss: () -> Void

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, cachedPlaybackInfo: PlaybackInfoResponse? = nil, onDismiss: @escaping () -> Void) {
        _viewModel = State(initialValue: PlayerViewModel(
            item: item,
            startFromBeginning: startFromBeginning,
            playbackService: playbackService,
            userID: userID,
            cachedPlaybackInfo: cachedPlaybackInfo
        ))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                // Native AVPlayerViewController owns the entire player UX —
                // scrubbing, transport bar, audio/subtitle picker, info
                // overlay, AirPlay, PiP. We just hand it the AVPlayer.
                NativeVideoPlayerView(player: viewModel.engine.player)
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .task {
            await viewModel.startPlayback()
        }
        .onDisappear {
            // Cut audio synchronously the moment the view leaves the
            // hierarchy. If we only do this in the async stopPlayback()
            // task, the player keeps decoding for ~1s while the dismiss
            // animation runs and the user hears audio bleed into the menu.
            viewModel.engine.stop()
            Task { await viewModel.stopPlayback() }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            Button { onDismiss() } label: {
                Text("home.retry")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
