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

                // Remote gesture handler
                RemoteTapHandler(
                    onTap: {
                        if viewModel.isScrubbing {
                            viewModel.commitScrub()
                        } else {
                            viewModel.toggleControls()
                        }
                    },
                    onPanChanged: { delta in
                        if !viewModel.isScrubbing {
                            viewModel.beginScrub()
                        }
                        viewModel.updateScrub(normalizedDelta: delta)
                    },
                    onPanEnded: {
                        viewModel.commitScrub()
                    }
                )
                .ignoresSafeArea()

                // Loading overlay
                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                        .transition(.opacity)
                }

                // Transport overlay (native tvOS style)
                if viewModel.showControls && !viewModel.isLoading {
                    gradientOverlays
                        .transition(.opacity)

                    VStack {
                        PlayerTitleOverlay(item: viewModel.item)
                        Spacer()
                    }
                    .transition(.opacity)

                    VStack {
                        Spacer()
                        TransportBar(
                            progress: viewModel.displayedProgress,
                            currentTime: viewModel.currentTime,
                            remainingTime: viewModel.remainingTime,
                            isScrubbing: viewModel.isScrubbing,
                            scrubTime: viewModel.scrubTime
                        )
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        .onPlayPauseCommand {
            viewModel.togglePlayPause()
        }
        .onExitCommand {
            if viewModel.isScrubbing {
                viewModel.cancelScrub()
            } else if viewModel.showControls {
                viewModel.showControls = false
            } else {
                dismissPlayer()
            }
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

    // MARK: - Gradient Overlays

    private var gradientOverlays: some View {
        ZStack {
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
