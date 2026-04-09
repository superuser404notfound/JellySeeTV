import SwiftUI

struct PlayerView: View {
    @State private var viewModel: PlayerViewModel
    let onDismiss: () -> Void

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, onDismiss: @escaping () -> Void) {
        _viewModel = State(initialValue: PlayerViewModel(
            item: item,
            startFromBeginning: startFromBeginning,
            playbackService: playbackService,
            userID: userID
        ))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                // VLC Video
                VLCPlayerWrapper(player: viewModel.coordinator.player)
                    .ignoresSafeArea()

                // Loading
                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                        .transition(.opacity)
                }

                // Transport overlay
                if viewModel.showControls && !viewModel.isLoading {
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

                // Invisible tap catcher for showing/hiding controls
                if !viewModel.isLoading {
                    Color.clear
                        .ignoresSafeArea()
                        .focusable()
                        .onPlayPauseCommand {
                            viewModel.togglePlayPause()
                        }
                        .onExitCommand {
                            dismissPlayer()
                        }
                        .onMoveCommand { direction in
                            switch direction {
                            case .left:
                                viewModel.seekBackward()
                            case .right:
                                viewModel.seekForward()
                            case .up, .down:
                                if viewModel.showControls {
                                    // Let focus system handle navigation to buttons
                                } else {
                                    viewModel.showControlsTemporarily()
                                }
                            @unknown default:
                                break
                            }
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
            viewModel.coordinator.stop()
            Task { await viewModel.stopPlayback() }
        }
    }

    private func dismissPlayer() {
        viewModel.coordinator.stop()
        Task {
            await viewModel.stopPlayback()
            onDismiss()
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
