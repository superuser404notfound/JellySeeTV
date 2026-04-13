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
                // Video layer
                SteelPlayerVideoView(videoLayer: viewModel.player.videoLayer)
                    .ignoresSafeArea()

                // Subtitle overlay
                if !viewModel.subtitleCues.isEmpty {
                    SubtitleOverlayView(
                        cues: viewModel.subtitleCues,
                        currentTime: viewModel.player.currentTime
                    )
                }

                // Remote input — disabled when track selection is open
                // so SwiftUI buttons can receive focus
                RemoteTapHandler(
                    isActive: !showTrackSelection,
                    onTap: handleTap,
                    onPlayPause: { viewModel.togglePlayPause() },
                    onMenu: handleMenu,
                    onLeft: { viewModel.seekBackward() },
                    onRight: { viewModel.seekForward() },
                    onPanChanged: { delta in viewModel.scrub(delta: delta) },
                    onPanEnded: { viewModel.commitScrub() }
                )
                .ignoresSafeArea()

                // Loading overlay
                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                        .transition(.opacity)
                }

                // Controls overlay
                if viewModel.showControls && !viewModel.isLoading {
                    controlsOverlay
                }

                // Track selection overlay
                if showTrackSelection {
                    trackSelectionOverlay
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        .animation(.easeInOut(duration: 0.2), value: showTrackSelection)
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

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            // Gradient overlays
            gradientOverlays

            // Title at top
            VStack {
                PlayerTitleOverlay(item: viewModel.item)
                Spacer()
            }

            // Transport bar at bottom
            VStack {
                Spacer()
                TransportBar(
                    progress: viewModel.displayedProgress,
                    currentTime: viewModel.currentTime,
                    remainingTime: viewModel.remainingTime,
                    isScrubbing: viewModel.isScrubbing,
                    scrubTime: viewModel.scrubTime,
                    hasTrackOptions: !viewModel.player.audioTracks.isEmpty || !viewModel.player.subtitleTracks.isEmpty,
                    onTrackButtonTapped: { showTrackSelection = true }
                )
            }
        }
        .transition(.opacity)
    }

    // MARK: - Track Selection Overlay

    private var trackSelectionOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showTrackSelection = false }

            VStack {
                Spacer()
                TrackSelectionView(
                    audioTracks: viewModel.player.audioTracks,
                    subtitleTracks: viewModel.player.subtitleTracks,
                    selectedAudioIndex: nil,
                    selectedSubtitleIndex: viewModel.activeSubtitleIndex,
                    onSelectAudio: { id in viewModel.selectAudioTrack(id: id) },
                    onSelectSubtitle: { id in viewModel.selectSubtitleTrack(id: id) },
                    onDismiss: { showTrackSelection = false }
                )
            }
        }
        .transition(.opacity)
    }

    // MARK: - Remote Input Handlers

    private func handleTap() {
        if showTrackSelection {
            showTrackSelection = false
            return
        }
        if viewModel.isScrubbing {
            viewModel.commitScrub()
            return
        }
        viewModel.handleClick()
    }

    private func handleMenu() {
        if showTrackSelection {
            showTrackSelection = false
        } else if viewModel.isScrubbing {
            viewModel.cancelScrub()
        } else if viewModel.showControls {
            viewModel.showControls = false
        } else {
            dismissPlayer()
        }
    }

    // MARK: - Helpers

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
                Text(String(localized: "home.retry", defaultValue: "Erneut versuchen"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
