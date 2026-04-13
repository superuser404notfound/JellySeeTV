import SwiftUI
import SteelPlayer

// MARK: - SwiftUI Wrapper (owns ViewModel + handles Menu)

/// SwiftUI wrapper that:
/// 1. Owns the PlayerViewModel (shared with the UIViewController)
/// 2. Handles Menu via .onExitCommand (tvOS intercepts Menu at the
///    presentation level — pressesBegan on a child VC never receives it)
/// 3. Contains the UIViewControllerRepresentable for the actual player
struct PlayerView: View {
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
        PlayerHostRepresentable(viewModel: viewModel)
            .ignoresSafeArea()
            .onExitCommand {
                handleMenu()
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
            viewModel.player.stop()
            Task {
                await viewModel.stopPlayback()
                onDismiss()
            }
        }
    }
}

// MARK: - UIViewControllerRepresentable

/// Bridges PlayerHostController into SwiftUI. The VC handles Select,
/// Arrows, Play/Pause, and Touchpad via pressesBegan/pressesEnded.
/// Menu is handled by the SwiftUI wrapper's .onExitCommand.
private struct PlayerHostRepresentable: UIViewControllerRepresentable {
    let viewModel: PlayerViewModel

    func makeUIViewController(context: Context) -> PlayerHostController {
        PlayerHostController(viewModel: viewModel)
    }

    func updateUIViewController(_ vc: PlayerHostController, context: Context) {}
}

// MARK: - Player View Controller

/// Full-screen video player controller.
///
/// Handles all Siri Remote input EXCEPT Menu (which tvOS intercepts
/// at the presentation level — handled by SwiftUI .onExitCommand).
///
/// Architecture:
/// ```
/// PlayerHostController (UIViewController)
/// ├── videoLayer (CALayer, direct sublayer)
/// ├── UIHostingController (child VC, display-only SwiftUI overlays)
/// │   └── PlayerOverlayView
/// └── UIPanGestureRecognizer (touchpad scrubbing)
/// ```
@MainActor
final class PlayerHostController: UIViewController {
    private let viewModel: PlayerViewModel

    init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
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

    // MARK: - Press Handling (Select, Arrows, Play/Pause — NOT Menu)

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed = false
        for press in presses {
            switch press.type {
            case .select, .playPause,
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
                    activeSubtitleIndex: viewModel.activeSubtitleIndex
                )
            }
        }
        .transition(.opacity)
    }
}
