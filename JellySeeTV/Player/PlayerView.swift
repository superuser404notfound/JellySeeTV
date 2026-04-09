import SwiftUI
import AVKit

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
                switch viewModel.engine {
                case .avPlayer:
                    avPlayerView
                case .vlcKit:
                    vlcPlayerView
                case .none:
                    EmptyView()
                }

                // Loading overlay (both engines)
                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .task {
            await viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.coordinator.stop()
            Task { await viewModel.stopPlayback() }
        }
    }

    // MARK: - AVPlayer (native tvOS controls)

    private var avPlayerView: some View {
        VideoPlayer(player: viewModel.coordinator.avPlayer)
            .ignoresSafeArea()
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                dismissPlayer()
            }
            .onExitCommand {
                dismissPlayer()
            }
    }

    // MARK: - VLCKit (custom controls)

    private var vlcPlayerView: some View {
        ZStack {
            VLCPlayerWrapper(player: viewModel.coordinator.vlcPlayer)
                .ignoresSafeArea()

            if viewModel.showControls {
                TransportOverlay(
                    title: viewModel.item.name,
                    isPlaying: viewModel.isPlaying,
                    currentTime: viewModel.currentTime,
                    totalTime: viewModel.totalTime,
                    progress: viewModel.progress,
                    audioTracks: viewModel.audioTracks,
                    subtitleTracks: viewModel.subtitleTracks,
                    currentAudioIndex: viewModel.currentAudioIndex,
                    currentSubtitleIndex: viewModel.currentSubtitleIndex,
                    onTogglePlayPause: { viewModel.togglePlayPause() },
                    onSeekForward: { viewModel.seekForward() },
                    onSeekBackward: { viewModel.seekBackward() },
                    onSelectAudio: { viewModel.setAudioTrack($0) },
                    onSelectSubtitle: { viewModel.setSubtitleTrack($0) }
                )
                .transition(.opacity)
            }

            // Input catcher for VLCKit mode
            Color.clear
                .ignoresSafeArea()
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
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
    }

    // MARK: - Dismiss

    private func dismissPlayer() {
        // Dismiss immediately, stop audio, then clean up async
        viewModel.coordinator.stop()
        onDismiss()
        Task { await viewModel.stopPlayback() }
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
