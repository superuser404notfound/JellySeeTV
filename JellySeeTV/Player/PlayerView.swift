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

                // Remote input (always active — handles both hidden and visible modes)
                RemoteTapHandler(
                    isActive: true,
                    onTap: handleTap,
                    onPlayPause: { viewModel.togglePlayPause() },
                    onMenu: handleMenu,
                    onLeft: handleLeft,
                    onRight: handleRight,
                    onPanChanged: { delta in viewModel.scrub(delta: delta) },
                    onPanEnded: {
                        // Update scrub start so next swipe continues from here
                        viewModel.scrubPanEnded()
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

                // Scrub preview (shown when scrubbing with UI hidden)
                if viewModel.isScrubbing && !viewModel.showControls {
                    scrubPreview
                }

                // Controls overlay (full UI)
                if viewModel.showControls && !viewModel.isLoading {
                    controlsOverlay
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

    // MARK: - Scrub Preview (UI hidden)

    private var scrubPreview: some View {
        VStack {
            Spacer()
            Text(viewModel.scrubTime)
                .font(.system(size: 56, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 120)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isScrubbing)
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
                    onSelectAudio: { id in viewModel.selectAudioTrack(id: id) },
                    onSelectSubtitle: { id in viewModel.selectSubtitleTrack(id: id) },
                    activeSubtitleIndex: viewModel.activeSubtitleIndex
                )
            }
        }
        .transition(.opacity)
    }

    // MARK: - Remote Input Handlers

    private func handleTap() {
        if viewModel.isScrubbing {
            // Confirm pending scrub/seek
            viewModel.commitScrub()
            return
        }

        if viewModel.showControls {
            // UI visible → toggle play/pause
            viewModel.togglePlayPause()
        } else {
            // UI hidden → show controls
            viewModel.showControlsTemporarily()
        }
    }

    private func handleMenu() {
        if viewModel.isScrubbing {
            viewModel.cancelScrub()
        } else if viewModel.showControls {
            viewModel.showControls = false
        } else {
            dismissPlayer()
        }
    }

    private func handleLeft() {
        viewModel.seekJump(seconds: -10)
    }

    private func handleRight() {
        viewModel.seekJump(seconds: 10)
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
