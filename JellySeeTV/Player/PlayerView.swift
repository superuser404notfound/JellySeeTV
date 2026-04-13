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
                SteelPlayerVideoView(videoLayer: viewModel.player.videoLayer)
                    .ignoresSafeArea()

                if !viewModel.subtitleCues.isEmpty {
                    SubtitleOverlayView(
                        cues: viewModel.subtitleCues,
                        currentTime: viewModel.player.currentTime
                    )
                }

                // Touchpad pan gesture (UIKit — works without focus)
                PanGestureView(
                    onPanChanged: { delta in viewModel.scrub(delta: delta) },
                    onPanEnded: { viewModel.scrubPanEnded() }
                )
                .ignoresSafeArea()

                // Invisible focusable target — receives Select press via Button action,
                // arrow keys via .onMoveCommand. SwiftUI gives this focus by default
                // since no other focusable view exists in the player hierarchy.
                Button(action: { handleTap() }) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .onMoveCommand { direction in
                    switch direction {
                    case .left: viewModel.seekJump(seconds: -10)
                    case .right: viewModel.seekJump(seconds: 10)
                    case .up, .down: viewModel.showControlsTemporarily()
                    @unknown default: break
                    }
                }

                // Loading overlay
                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
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
        // SwiftUI commands — work on the focused Button
        .onPlayPauseCommand { viewModel.togglePlayPause() }
        .onExitCommand { handleMenu() }
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
                    activeSubtitleIndex: viewModel.activeSubtitleIndex
                )
            }
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Input Handlers

    private func handleTap() {
        #if DEBUG
        print("[Player] handleTap: showControls=\(viewModel.showControls), scrubbing=\(viewModel.isScrubbing)")
        #endif
        if viewModel.isScrubbing {
            viewModel.commitScrub()
        } else if viewModel.showControls {
            viewModel.togglePlayPause()
        } else {
            viewModel.showControlsTemporarily()
        }
    }

    private func handleMenu() {
        #if DEBUG
        print("[Player] handleMenu: showControls=\(viewModel.showControls), scrubbing=\(viewModel.isScrubbing)")
        #endif
        if viewModel.isScrubbing {
            viewModel.cancelScrub()
        } else if viewModel.showControls {
            viewModel.hideControls()
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
                Text(String(localized: "home.retry", defaultValue: "Try Again"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
