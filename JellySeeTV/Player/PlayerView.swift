import SwiftUI

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
                // Video layer (UIView that VLC renders into)
                VideoLayerView(drawableView: viewModel.engine.drawableView)
                    .ignoresSafeArea()

                // Single remote input handler — captures ALL Siri Remote events
                RemoteTapHandler(
                    onTap: {
                        if viewModel.isScrubbing && viewModel.didMoveScrub {
                            // Click during real scrub commits the seek
                            viewModel.commitScrub()
                        } else {
                            // No real scrub → cancel any stale scrub state, do normal click
                            viewModel.cancelScrub()
                            viewModel.handleClick()
                        }
                    },
                    onPlayPause: {
                        // Cancel any stale scrub state first
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
                        // First pan in this gesture sequence starts/continues scrub
                        if !viewModel.isScrubbing {
                            viewModel.beginScrub()
                        }
                        viewModel.updateScrub(normalizedDelta: delta)
                    },
                    onPanEnded: {
                        // Stay in scrub mode — user must click to confirm.
                        // Re-baseline so the NEXT pan starts from the current
                        // scrub position (not the engine playback position).
                        if viewModel.isScrubbing {
                            viewModel.continueScrub()
                        }
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
        .task {
            await viewModel.startPlayback()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Pause when going to background — VLC's video output is GL-backed
            // and can't draw without an active scene.
            if newPhase == .background || newPhase == .inactive {
                viewModel.engine.pause()
            }
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
