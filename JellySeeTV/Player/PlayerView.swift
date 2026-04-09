import SwiftUI

struct PlayerView: View {
    @State private var viewModel: PlayerViewModel
    let onDismiss: () -> Void

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, cachedPlaybackInfo: PlaybackInfoResponse? = nil, cachedDemuxer: Demuxer? = nil, onDismiss: @escaping () -> Void) {
        _viewModel = State(initialValue: PlayerViewModel(
            item: item,
            startFromBeginning: startFromBeginning,
            playbackService: playbackService,
            userID: userID,
            cachedPlaybackInfo: cachedPlaybackInfo,
            cachedDemuxer: cachedDemuxer
        ))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                // Video layer
                VideoLayerView(renderer: viewModel.engine.videoRenderer)
                    .ignoresSafeArea()

                // Loading overlay
                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                        .transition(.opacity)
                }

                // Transport UI (native tvOS style)
                if viewModel.showControls && !viewModel.isLoading {
                    transportUI
                        .transition(.opacity)
                }

                // Bottom gradient (always visible when controls shown, helps readability)
                if viewModel.showControls && !viewModel.isLoading {
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 300)
                        .allowsHitTesting(false)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)

                    // Top gradient for title
                    VStack {
                        LinearGradient(
                            colors: [.black.opacity(0.7), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 200)
                        .allowsHitTesting(false)
                        Spacer()
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        .focusable()
        .onPlayPauseCommand {
            viewModel.togglePlayPause()
        }
        .onExitCommand {
            dismissPlayer()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: viewModel.seekBackward()
            case .right: viewModel.seekForward()
            default: viewModel.showControlsTemporarily()
            }
        }
        .task {
            await viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.engine.stop()
            Task { await viewModel.stopPlayback() }
        }
    }

    // MARK: - Native Transport UI

    private var transportUI: some View {
        ZStack {
            // Title at top
            VStack {
                PlayerTitleOverlay(item: viewModel.item)
                Spacer()
            }

            // Transport bar at bottom
            VStack {
                Spacer()
                TransportBar(
                    progress: viewModel.progress,
                    currentTime: viewModel.currentTime,
                    remainingTime: viewModel.remainingTime,
                    isPlaying: viewModel.isPlaying,
                    onSeekBackward: { viewModel.seekBackward() },
                    onTogglePlayPause: { viewModel.togglePlayPause() },
                    onSeekForward: { viewModel.seekForward() }
                )
            }
        }
    }

    // MARK: - Dismiss

    private func dismissPlayer() {
        viewModel.engine.stop()
        Task {
            await viewModel.stopPlayback()
            onDismiss()
        }
    }

    // MARK: - Error

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
