import SwiftUI
import SteelPlayer

struct PlayerView: View {
    @Environment(\.scenePhase) private var scenePhase
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

                // Remote input — ALWAYS active, callbacks are state-aware.
                // No .onExitCommand / .onPlayPauseCommand — they conflict
                // with UIKit focus on tvOS.
                RemoteTapHandler(
                    onTap: handleTap,
                    onPlayPause: { viewModel.togglePlayPause() },
                    onMenu: handleMenu,
                    onLeft: handleLeft,
                    onRight: handleRight,
                    onUp: { viewModel.navigateUp() },
                    onDown: handleDown,
                    onPanChanged: { delta in viewModel.scrub(delta: delta) },
                    onPanEnded: { viewModel.scrubPanEnded() }
                )
                .ignoresSafeArea()

                // Loading overlay — focusable(false) prevents ProgressView
                // from stealing focus from RemoteTapHandler on tvOS.
                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView().focusable(false))
                        .focusable(false)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Controls overlay
                if viewModel.showControls && !viewModel.isLoading {
                    controlsOverlay
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        // Track selection dialogs — presented modally, handle their own focus
        .confirmationDialog(
            String(localized: "player.audio", defaultValue: "Audio"),
            isPresented: $viewModel.showAudioPicker
        ) {
            ForEach(viewModel.player.audioTracks) { track in
                Button(track.name) { viewModel.selectAudioTrack(id: track.id) }
            }
        }
        .confirmationDialog(
            String(localized: "player.subtitles", defaultValue: "Subtitles"),
            isPresented: $viewModel.showSubtitlePicker
        ) {
            Button(String(localized: "player.subtitles.off", defaultValue: "Off")) {
                viewModel.selectSubtitleTrack(id: nil)
            }
            ForEach(viewModel.player.subtitleTracks) { track in
                Button(track.name) { viewModel.selectSubtitleTrack(id: track.id) }
            }
        }
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
            gradientOverlays

            VStack {
                PlayerTitleOverlay(item: viewModel.item)
                Spacer()
            }

            VStack {
                Spacer()
                TransportBar(
                    progress: viewModel.displayedProgress,
                    currentTime: viewModel.currentTime,
                    remainingTime: viewModel.remainingTime,
                    isScrubbing: viewModel.isScrubbing,
                    scrubTime: viewModel.scrubTime,
                    audioTracks: viewModel.player.audioTracks,
                    subtitleTracks: viewModel.player.subtitleTracks,
                    activeSubtitleIndex: viewModel.activeSubtitleIndex,
                    controlsFocus: viewModel.controlsFocus
                )
            }
        }
        .transition(.opacity)
    }

    // MARK: - Remote Input Handlers (state-aware)

    private func handleTap() {
        if viewModel.isScrubbing {
            viewModel.commitScrub()
        } else if viewModel.showControls {
            // Controls visible — check if a track button is focused
            if viewModel.controlsFocus == .progressBar {
                viewModel.togglePlayPause()
            } else {
                viewModel.activateControlsFocus()
            }
        } else {
            // Controls hidden → show
            viewModel.showControlsTemporarily()
        }
    }

    private func handleMenu() {
        if viewModel.isScrubbing {
            viewModel.cancelScrub()
        } else if viewModel.showControls {
            if viewModel.controlsFocus != .progressBar {
                // On a track button → go back to progress bar
                viewModel.controlsFocus = .progressBar
            } else {
                // On progress bar → hide controls
                viewModel.showControls = false
            }
        } else {
            // Controls hidden → dismiss player
            dismissPlayer()
        }
    }

    private func handleLeft() {
        if viewModel.showControls && viewModel.controlsFocus != .progressBar {
            viewModel.navigateLeftInControls()
        } else {
            viewModel.seekJump(seconds: -10)
        }
    }

    private func handleRight() {
        if viewModel.showControls && viewModel.controlsFocus != .progressBar {
            viewModel.navigateRightInControls()
        } else {
            viewModel.seekJump(seconds: 10)
        }
    }

    private func handleDown() {
        if viewModel.showControls {
            viewModel.navigateDown()
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
                Text(String(localized: "home.retry", defaultValue: "Try Again"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
