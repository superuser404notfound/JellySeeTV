import SwiftUI
import GameController

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
                // VLC Video output
                VLCPlayerWrapper(player: viewModel.coordinator.player)
                    .ignoresSafeArea()

                // Loading overlay
                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                        .transition(.opacity)
                }

                // Transport controls overlay
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
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        .task {
            await viewModel.startPlayback()
        }
        .onAppear { setupRemoteHandling() }
        .onDisappear {
            viewModel.coordinator.stop()
            Task { await viewModel.stopPlayback() }
        }
    }

    // MARK: - Siri Remote

    private func setupRemoteHandling() {
        // Menu button = exit player
        let menuPress = UITapGestureRecognizer(target: RemoteHandler.shared, action: #selector(RemoteHandler.menuPressed))
        menuPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        RemoteHandler.shared.onMenu = { [onDismiss] in
            Task { @MainActor in
                await viewModel.stopPlayback()
                onDismiss()
            }
        }

        // Play/Pause button
        let playPausePress = UITapGestureRecognizer(target: RemoteHandler.shared, action: #selector(RemoteHandler.playPausePressed))
        playPausePress.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        RemoteHandler.shared.onPlayPause = {
            viewModel.togglePlayPause()
        }

        // Select button (tap on trackpad) = show/hide controls
        let selectPress = UITapGestureRecognizer(target: RemoteHandler.shared, action: #selector(RemoteHandler.selectPressed))
        selectPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        RemoteHandler.shared.onSelect = {
            if viewModel.showControls {
                viewModel.hideControls()
            } else {
                viewModel.showControlsTemporarily()
            }
        }

        // Swipe left/right for seeking
        let swipeLeft = UISwipeGestureRecognizer(target: RemoteHandler.shared, action: #selector(RemoteHandler.swipedLeft))
        swipeLeft.direction = .left
        RemoteHandler.shared.onSwipeLeft = { viewModel.seekBackward() }

        let swipeRight = UISwipeGestureRecognizer(target: RemoteHandler.shared, action: #selector(RemoteHandler.swipedRight))
        swipeRight.direction = .right
        RemoteHandler.shared.onSwipeRight = { viewModel.seekForward() }

        // Add gestures to the key window
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            // Remove old gestures
            window.gestureRecognizers?.forEach { window.removeGestureRecognizer($0) }
            window.addGestureRecognizer(menuPress)
            window.addGestureRecognizer(playPausePress)
            window.addGestureRecognizer(selectPress)
            window.addGestureRecognizer(swipeLeft)
            window.addGestureRecognizer(swipeRight)
        }
    }

    // MARK: - Error View

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

// MARK: - Remote Handler (ObjC target for gesture recognizers)

@MainActor
final class RemoteHandler: NSObject {
    static let shared = RemoteHandler()

    var onMenu: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onSelect: (() -> Void)?
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?

    @objc func menuPressed() { onMenu?() }
    @objc func playPausePressed() { onPlayPause?() }
    @objc func selectPressed() { onSelect?() }
    @objc func swipedLeft() { onSwipeLeft?() }
    @objc func swipedRight() { onSwipeRight?() }
}
