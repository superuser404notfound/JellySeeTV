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

    // MARK: - Press Handlers (state machine)

    @objc private func selectPressed() {
        if viewModel.isDropdownOpen {
            confirmDropdownSelection()
        } else if viewModel.isScrubbing {
            viewModel.commitScrub()
        } else if viewModel.showControls {
            switch viewModel.controlsFocus {
            case .progressBar:
                viewModel.togglePlayPause()
            case .audioButton:
                openAudioDropdown()
            case .subtitleButton:
                openSubtitleDropdown()
            }
        } else {
            viewModel.showControlsTemporarily()
        }
    }

    @objc private func playPausePressed() {
        viewModel.togglePlayPause()
    }

    @objc private func menuPressed() {
        if viewModel.isDropdownOpen {
            viewModel.trackDropdown = .none
            viewModel.scheduleControlsHide()
        } else if viewModel.isScrubbing {
            viewModel.cancelScrub()
        } else if viewModel.showControls {
            if viewModel.controlsFocus != .progressBar {
                viewModel.controlsFocus = .progressBar
            } else {
                viewModel.hideControls()
            }
        } else {
            dismissPlayer()
        }
    }

    @objc private func leftPressed() {
        if viewModel.isDropdownOpen { return }
        if viewModel.showControls && viewModel.controlsFocus == .subtitleButton {
            if !viewModel.player.audioTracks.isEmpty {
                viewModel.controlsFocus = .audioButton
            }
        } else {
            viewModel.seekJump(seconds: -10)
        }
    }

    @objc private func rightPressed() {
        if viewModel.isDropdownOpen { return }
        if viewModel.showControls && viewModel.controlsFocus == .audioButton {
            if !viewModel.player.subtitleTracks.isEmpty {
                viewModel.controlsFocus = .subtitleButton
            }
        } else {
            viewModel.seekJump(seconds: 10)
        }
    }

    @objc private func upPressed() {
        if viewModel.isDropdownOpen {
            moveDropdownHighlight(by: -1)
        } else if viewModel.showControls {
            switch viewModel.controlsFocus {
            case .progressBar:
                if viewModel.isScrubbing { viewModel.cancelScrub() }
                let hasAudio = !viewModel.player.audioTracks.isEmpty
                let hasSubs = !viewModel.player.subtitleTracks.isEmpty
                if hasAudio { viewModel.controlsFocus = .audioButton }
                else if hasSubs { viewModel.controlsFocus = .subtitleButton }
            case .audioButton, .subtitleButton:
                break
            }
        } else {
            viewModel.showControlsTemporarily()
        }
    }

    @objc private func downPressed() {
        if viewModel.isDropdownOpen {
            moveDropdownHighlight(by: 1)
        } else if viewModel.showControls {
            if viewModel.controlsFocus != .progressBar {
                viewModel.controlsFocus = .progressBar
            } else {
                viewModel.hideControls()
            }
        } else {
            viewModel.showControlsTemporarily()
        }
    }

    // MARK: - Dropdown Logic

    private func openAudioDropdown() {
        let tracks = viewModel.player.audioTracks
        guard !tracks.isEmpty else { return }
        viewModel.controlsTimer?.cancel()
        let currentIdx = tracks.firstIndex(where: { $0.id == viewModel.activeAudioIndex }) ?? 0
        viewModel.trackDropdown = .audio(highlighted: currentIdx)
    }

    private func openSubtitleDropdown() {
        viewModel.controlsTimer?.cancel()
        // Items: Off (index 0), then each subtitle track (index 1...)
        let currentIdx: Int
        if let activeId = viewModel.activeSubtitleIndex,
           let trackIdx = viewModel.player.subtitleTracks.firstIndex(where: { $0.id == activeId }) {
            currentIdx = trackIdx + 1
        } else {
            currentIdx = 0
        }
        viewModel.trackDropdown = .subtitle(highlighted: currentIdx)
    }

    private func moveDropdownHighlight(by offset: Int) {
        switch viewModel.trackDropdown {
        case .audio(let idx):
            let count = viewModel.player.audioTracks.count
            guard count > 0 else { return }
            let newIdx = max(0, min(count - 1, idx + offset))
            viewModel.trackDropdown = .audio(highlighted: newIdx)
        case .subtitle(let idx):
            let count = viewModel.player.subtitleTracks.count + 1 // +1 for "Off"
            guard count > 0 else { return }
            let newIdx = max(0, min(count - 1, idx + offset))
            viewModel.trackDropdown = .subtitle(highlighted: newIdx)
        case .none:
            break
        }
    }

    private func confirmDropdownSelection() {
        switch viewModel.trackDropdown {
        case .audio(let idx):
            let tracks = viewModel.player.audioTracks
            if idx < tracks.count {
                viewModel.selectAudioTrack(id: tracks[idx].id)
            }
            viewModel.trackDropdown = .none
            viewModel.scheduleControlsHide()
        case .subtitle(let idx):
            if idx == 0 {
                viewModel.selectSubtitleTrack(id: nil)
            } else {
                let tracks = viewModel.player.subtitleTracks
                let trackIdx = idx - 1
                if trackIdx < tracks.count {
                    viewModel.selectSubtitleTrack(id: tracks[trackIdx].id)
                }
            }
            viewModel.trackDropdown = .none
            viewModel.scheduleControlsHide()
        case .none:
            break
        }
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
                    activeSubtitleIndex: viewModel.activeSubtitleIndex,
                    controlsFocus: viewModel.controlsFocus,
                    trackDropdown: viewModel.trackDropdown
                )
            }
        }
        .transition(.opacity)
    }
}
