import SwiftUI
import SteelPlayer

// MARK: - SwiftUI Bridge

/// UIViewControllerRepresentable that wraps PlayerHostController.
/// The UIViewController handles ALL Siri Remote input via pressesBegan/
/// pressesEnded — no focus issues, no gesture recognizer routing issues.
struct PlayerView: UIViewControllerRepresentable {
    let item: JellyfinItem
    let startFromBeginning: Bool
    let playbackService: JellyfinPlaybackServiceProtocol
    let userID: String
    var cachedPlaybackInfo: PlaybackInfoResponse?
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PlayerHostController {
        let vm = PlayerViewModel(
            item: item,
            startFromBeginning: startFromBeginning,
            playbackService: playbackService,
            userID: userID,
            cachedPlaybackInfo: cachedPlaybackInfo
        )
        return PlayerHostController(viewModel: vm, onDismiss: onDismiss)
    }

    func updateUIViewController(_ vc: PlayerHostController, context: Context) {}
}

// MARK: - Player View Controller

/// Full-screen video player controller that captures ALL Siri Remote input.
///
/// Architecture:
/// ```
/// PlayerHostController (UIViewController)
/// ├── videoLayer (CALayer, direct sublayer)
/// ├── UIHostingController (child VC, SwiftUI overlays)
/// │   └── PlayerOverlayView (display-only, allowsHitTesting=false)
/// │       ├── SubtitleOverlayView
/// │       ├── Loading spinner
/// │       └── Controls (gradients, title, TransportBar)
/// └── UIPanGestureRecognizer (touchpad scrubbing)
/// ```
///
/// Press events flow directly to this VC — no focus system involved.
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

        // Video layer — added directly, no UIViewRepresentable wrapper needed
        let videoLayer = viewModel.player.videoLayer
        view.layer.addSublayer(videoLayer)

        // SwiftUI overlays (subtitles, loading, controls) — display only
        let overlay = PlayerOverlayView(viewModel: viewModel)
        let hosting = UIHostingController(rootView: overlay)
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = false
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hosting.didMove(toParent: self)

        // Touchpad pan gesture for scrubbing
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        // Background/inactive → pause
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )

        // Start playback
        Task { await viewModel.startPlayback() }
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

    // MARK: - Press Handling

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed = false
        for press in presses {
            switch press.type {
            case .select, .playPause, .menu,
                 .leftArrow, .rightArrow, .upArrow, .downArrow:
                consumed = true
            default:
                break
            }
        }
        if !consumed { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed = false
        for press in presses {
            switch press.type {
            case .select:
                handleTap()
                consumed = true
            case .playPause:
                viewModel.togglePlayPause()
                consumed = true
            case .menu:
                handleMenu()
                consumed = true
            case .leftArrow:
                viewModel.seekJump(seconds: -10)
                consumed = true
            case .rightArrow:
                viewModel.seekJump(seconds: 10)
                consumed = true
            case .upArrow, .downArrow:
                viewModel.showControlsTemporarily()
                consumed = true
            default:
                break
            }
        }
        if !consumed { super.pressesEnded(presses, with: event) }
    }

    // MARK: - Input Logic

    private func handleTap() {
        if viewModel.isScrubbing {
            viewModel.commitScrub()
        } else if viewModel.showControls {
            viewModel.togglePlayPause()
        } else {
            viewModel.showControlsTemporarily()
        }
    }

    private func handleMenu() {
        if viewModel.isScrubbing {
            viewModel.cancelScrub()
        } else if viewModel.showControls {
            viewModel.hideControls()
        } else {
            dismissPlayer()
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

/// All visual overlays rendered by SwiftUI. This view has
/// `isUserInteractionEnabled = false` on its hosting controller —
/// purely display, no focus or input handling.
private struct PlayerOverlayView: View {
    let viewModel: PlayerViewModel

    var body: some View {
        ZStack {
            // Subtitles
            if !viewModel.subtitleCues.isEmpty {
                SubtitleOverlayView(
                    cues: viewModel.subtitleCues,
                    currentTime: viewModel.player.currentTime
                )
            }

            // Loading
            if viewModel.isLoading {
                Color.black
                    .ignoresSafeArea()
                    .overlay(ProgressView())
                    .transition(.opacity)
            }

            // Error
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

            // Controls
            if viewModel.showControls && !viewModel.isLoading && viewModel.errorMessage == nil {
                controlsOverlay
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
    }

    private var controlsOverlay: some View {
        ZStack {
            // Bottom gradient
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 300)
            }
            .ignoresSafeArea()

            // Top gradient
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
                Spacer()
            }
            .ignoresSafeArea()

            // Title
            VStack {
                PlayerTitleOverlay(item: viewModel.item)
                Spacer()
            }

            // Transport bar
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
    }
}
