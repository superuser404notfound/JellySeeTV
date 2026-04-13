import SwiftUI
import SteelPlayer

struct PlayerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: PlayerViewModel
    @State private var showTrackSelection = false
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
                // SteelPlayer's video layer — AVSampleBufferDisplayLayer
                // for optimal frame pacing and A/V sync
                SteelPlayerVideoView(videoLayer: viewModel.player.videoLayer)
                    .ignoresSafeArea()

                // Siri Remote handler
                RemoteTapHandler(
                    onTap: {
                        if viewModel.isScrubbing && viewModel.didMoveScrub {
                            viewModel.commitScrub()
                        } else {
                            viewModel.cancelScrub()
                            viewModel.handleClick()
                        }
                    },
                    onPlayPause: {
                        viewModel.cancelScrub()
                        viewModel.togglePlayPause()
                    },
                    onMenu: {
                        if viewModel.isScrubbing {
                            viewModel.cancelScrub()
                        } else if viewModel.showControls {
                            viewModel.showControls = false
                        } else {
                            dismissPlayer()
                        }
                    },
                    onLeft: {
                        viewModel.cancelScrub()
                        viewModel.seekBackward()
                    },
                    onRight: {
                        viewModel.cancelScrub()
                        viewModel.seekForward()
                    },
                    onPanChanged: { delta in
                        if !viewModel.isScrubbing {
                            viewModel.beginScrub()
                        }
                        viewModel.updateScrub(normalizedDelta: delta)
                    },
                    onPanEnded: {
                        if viewModel.isScrubbing {
                            viewModel.continueScrub()
                        }
                    }
                )
                .ignoresSafeArea()

                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                        .transition(.opacity)
                }

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
                            scrubTime: viewModel.scrubTime,
                            hasTrackOptions: !viewModel.player.audioTracks.isEmpty || !viewModel.player.subtitleTracks.isEmpty,
                            onTrackButtonTapped: {
                                showTrackSelection.toggle()
                            }
                        )
                    }
                    .transition(.opacity)

                    // Track selection overlay
                    if showTrackSelection {
                        VStack {
                            Spacer()
                            TrackSelectionView(
                                audioTracks: viewModel.player.audioTracks,
                                subtitleTracks: viewModel.player.subtitleTracks,
                                selectedAudioIndex: nil, // TODO: track active selection
                                selectedSubtitleIndex: nil,
                                onSelectAudio: { id in
                                    viewModel.selectAudioTrack(id: id)
                                },
                                onSelectSubtitle: { id in
                                    if let id {
                                        viewModel.selectSubtitleTrack(id: id)
                                    }
                                    // TODO: subtitle off
                                },
                                onDismiss: { showTrackSelection = false }
                            )
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        .task {
            await viewModel.startPlayback()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                viewModel.player.pause()
            }
        }
        .onDisappear {
            viewModel.player.stop()
            Task { await viewModel.stopPlayback() }
        }
    }

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

    private func dismissPlayer() {
        viewModel.player.stop()
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
