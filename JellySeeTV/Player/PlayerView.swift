import SwiftUI
import SteelPlayer

// MARK: - Player Launcher (UIKit modal presentation)

/// Presents PlayerHostController as a UIKit modal (NOT SwiftUI fullScreenCover).
///
/// On tvOS, SwiftUI's fullScreenCover intercepts the Menu button at the
/// presentation level — pressesBegan, .onExitCommand, and gesture recognizers
/// on child VCs never receive it. UIKit modals don't have this problem:
/// UITapGestureRecognizer for .menu on the presented VC's view works.
struct PlayerLauncher: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let item: JellyfinItem
    let startFromBeginning: Bool
    let playbackService: JellyfinPlaybackServiceProtocol
    let userID: String
    var cachedPlaybackInfo: PlaybackInfoResponse?

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        if isPresented && host.presentedViewController == nil {
            let vm = PlayerViewModel(
                item: item,
                startFromBeginning: startFromBeginning,
                playbackService: playbackService,
                userID: userID,
                cachedPlaybackInfo: cachedPlaybackInfo
            )
            let player = PlayerHostController(viewModel: vm, onDismiss: {
                host.dismiss(animated: false) {
                    isPresented = false
                }
            })
            player.modalPresentationStyle = .fullScreen
            host.present(player, animated: false)
        } else if !isPresented, host.presentedViewController != nil {
            host.dismiss(animated: false)
        }
    }
}

// MARK: - Player View Controller

/// Full-screen video player that handles ALL Siri Remote input.
///
/// Presented via UIKit `present(_:animated:)` — NOT SwiftUI fullScreenCover.
/// This is critical: UIKit modals allow UITapGestureRecognizer to intercept
/// the Menu button, while SwiftUI fullScreenCover steals it at the
/// presentation level.
@MainActor
final class PlayerHostController: UIViewController {
    private let viewModel: PlayerViewModel
    private let onDismiss: () -> Void

    init(viewModel: PlayerViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Video layer
        view.layer.addSublayer(viewModel.player.videoLayer)

        // SwiftUI overlays (display-only)
        let overlay = PlayerOverlayView(viewModel: viewModel)
        let hosting = UIHostingController(rootView: overlay)
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = false
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hosting.didMove(toParent: self)

        // Gesture recognizers for ALL buttons including Menu
        addPressGesture(.select, action: #selector(selectPressed))
        addPressGesture(.playPause, action: #selector(playPausePressed))
        addPressGesture(.menu, action: #selector(menuPressed))
        addPressGesture(.leftArrow, action: #selector(leftPressed))
        addPressGesture(.rightArrow, action: #selector(rightPressed))
        addPressGesture(.upArrow, action: #selector(upPressed))
        addPressGesture(.downArrow, action: #selector(downPressed))

        // Touchpad pan gesture
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        // Background → pause
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )

        Task { await viewModel.startPlayback() }
    }

    private func addPressGesture(_ type: UIPress.PressType, action: Selector) {
        let tap = UITapGestureRecognizer(target: self, action: action)
        tap.allowedPressTypes = [NSNumber(value: type.rawValue)]
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        viewModel.player.videoLayer.frame = view.bounds
        CATransaction.commit()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.player.stop()
        Task { await viewModel.stopPlayback() }
    }

    @objc private func appWillResignActive() {
        viewModel.player.pause()
    }

    // MARK: - Press Handlers

    @objc private func selectPressed() {
        #if DEBUG
        print("[Player] select: showControls=\(viewModel.showControls), scrubbing=\(viewModel.isScrubbing)")
        #endif
        if viewModel.isScrubbing {
            viewModel.commitScrub()
        } else if viewModel.showControls {
            viewModel.togglePlayPause()
        } else {
            viewModel.showControlsTemporarily()
        }
    }

    @objc private func playPausePressed() {
        viewModel.togglePlayPause()
    }

    @objc private func menuPressed() {
        #if DEBUG
        print("[Player] menu: showControls=\(viewModel.showControls), scrubbing=\(viewModel.isScrubbing)")
        #endif
        if viewModel.isScrubbing {
            viewModel.cancelScrub()
        } else if viewModel.showControls {
            viewModel.hideControls()
        } else {
            dismissPlayer()
        }
    }

    @objc private func leftPressed() {
        viewModel.seekJump(seconds: -10)
    }

    @objc private func rightPressed() {
        viewModel.seekJump(seconds: 10)
    }

    @objc private func upPressed() {
        if viewModel.showControls {
            showTrackPicker()
        } else {
            viewModel.showControlsTemporarily()
        }
    }

    @objc private func downPressed() {
        viewModel.showControlsTemporarily()
    }

    // MARK: - Track Picker (UIAlertController)

    private func showTrackPicker() {
        let audioTracks = viewModel.player.audioTracks
        let subtitleTracks = viewModel.player.subtitleTracks
        guard !audioTracks.isEmpty || !subtitleTracks.isEmpty else { return }

        // Cancel auto-hide while picker is open
        viewModel.controlsTimer?.cancel()

        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        // Audio section
        for track in audioTracks {
            let isActive = track.id == viewModel.activeAudioIndex
            let action = UIAlertAction(
                title: track.name,
                style: .default
            ) { [weak self] _ in
                self?.viewModel.selectAudioTrack(id: track.id)
                self?.viewModel.scheduleControlsHide()
            }
            action.setValue(
                UIImage(systemName: isActive ? "speaker.wave.2.fill" : "speaker.wave.2"),
                forKey: "image"
            )
            if isActive { action.setValue(true, forKey: "checked") }
            alert.addAction(action)
        }

        // Separator — subtitle header
        if !audioTracks.isEmpty && !subtitleTracks.isEmpty {
            let header = UIAlertAction(
                title: String(localized: "player.subtitles", defaultValue: "Subtitles"),
                style: .default,
                handler: { _ in }
            )
            header.isEnabled = false
            alert.addAction(header)
        }

        // Subtitle: Off
        let offAction = UIAlertAction(
            title: String(localized: "player.subtitles.off", defaultValue: "Off"),
            style: .default
        ) { [weak self] _ in
            self?.viewModel.selectSubtitleTrack(id: nil)
            self?.viewModel.scheduleControlsHide()
        }
        if viewModel.activeSubtitleIndex == nil {
            offAction.setValue(true, forKey: "checked")
        }
        alert.addAction(offAction)

        // Subtitle tracks
        for track in subtitleTracks {
            let isActive = track.id == viewModel.activeSubtitleIndex
            let action = UIAlertAction(
                title: track.name,
                style: .default
            ) { [weak self] _ in
                self?.viewModel.selectSubtitleTrack(id: track.id)
                self?.viewModel.scheduleControlsHide()
            }
            if isActive { action.setValue(true, forKey: "checked") }
            alert.addAction(action)
        }

        // Cancel
        alert.addAction(UIAlertAction(
            title: String(localized: "player.trackpicker.cancel", defaultValue: "Cancel"),
            style: .cancel
        ) { [weak self] _ in
            self?.viewModel.scheduleControlsHide()
        })

        present(alert, animated: true)
    }

    private func dismissPlayer() {
        viewModel.player.stop()
        Task {
            await viewModel.stopPlayback()
            onDismiss()
        }
    }

    // MARK: - Pan (Touchpad Scrubbing)

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let width = max(view.bounds.width, 1)
            let normalized = gesture.translation(in: view).x / width
            viewModel.scrub(delta: normalized)
        case .ended, .cancelled:
            viewModel.scrubPanEnded()
        default:
            break
        }
    }
}

// MARK: - Overlay View (display-only SwiftUI)

private struct PlayerOverlayView: View {
    let viewModel: PlayerViewModel

    var body: some View {
        ZStack {
            if !viewModel.subtitleCues.isEmpty {
                SubtitleOverlayView(
                    cues: viewModel.subtitleCues,
                    currentTime: viewModel.player.currentTime
                )
            }

            if viewModel.isLoading {
                Color.black
                    .ignoresSafeArea()
                    .overlay(ProgressView())
                    .transition(.opacity)
            }

            if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }

            if viewModel.showControls && !viewModel.isLoading && viewModel.errorMessage == nil {
                controlsOverlay
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
    }

    private var controlsOverlay: some View {
        ZStack {
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 300)
            }
            .ignoresSafeArea()

            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
                Spacer()
            }
            .ignoresSafeArea()

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
                    activeAudioIndex: viewModel.activeAudioIndex,
                    activeSubtitleIndex: viewModel.activeSubtitleIndex
                )
            }
        }
        .transition(.opacity)
    }
}
