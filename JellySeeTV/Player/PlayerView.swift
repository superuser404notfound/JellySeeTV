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

                // When controls hidden: invisible focusable to catch remote input
                if !viewModel.showControls && !viewModel.isLoading {
                    Color.clear
                        .focusable()
                        .onMoveCommand { direction in
                            switch direction {
                            case .left: viewModel.seekBackward()
                            case .right: viewModel.seekForward()
                            default: viewModel.showControlsTemporarily()
                            }
                        }
                        .onPlayPauseCommand {
                            viewModel.togglePlayPause()
                        }
                        .onExitCommand {
                            dismissPlayer()
                        }
                }

                // Transport UI (native tvOS style)
                if viewModel.showControls && !viewModel.isLoading {
                    // Gradients for readability
                    gradientOverlays
                        .transition(.opacity)

                    // Title at top
                    VStack {
                        PlayerTitleOverlay(item: viewModel.item)
                        Spacer()
                    }
                    .transition(.opacity)

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
                    .transition(.opacity)
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
                    .onPlayPauseCommand {
                        viewModel.togglePlayPause()
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        .task {
            await viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.engine.stop()
            Task { await viewModel.stopPlayback() }
        }
    }

    // MARK: - Gradient Overlays

    private var gradientOverlays: some View {
        ZStack {
            // Bottom gradient
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 300)
            }
            .ignoresSafeArea()

            // Top gradient
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
                Spacer()
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
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
