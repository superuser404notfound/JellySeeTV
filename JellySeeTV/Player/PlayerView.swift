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

                // Transport controls
                if viewModel.showControls && !viewModel.isLoading {
                    transportOverlay
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        .focusable()
        .onPlayPauseCommand { viewModel.togglePlayPause() }
        .onExitCommand { dismissPlayer() }
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

    // MARK: - Transport Overlay

    private var transportOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Text(viewModel.item.name)
                    .font(.headline)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2)).frame(height: 6)
                        Capsule().fill(.tint).frame(
                            width: max(0, geo.size.width * CGFloat(viewModel.progress)),
                            height: 6
                        )
                    }
                }
                .frame(height: 6)

                // Time + controls
                HStack {
                    Text(viewModel.currentTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 30) {
                        Button { viewModel.seekBackward() } label: {
                            Image(systemName: "gobackward.10").font(.title3)
                        }
                        .buttonStyle(.plain)

                        Button { viewModel.togglePlayPause() } label: {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)

                        Button { viewModel.seekForward() } label: {
                            Image(systemName: "goforward.10").font(.title3)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(viewModel.totalTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
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
