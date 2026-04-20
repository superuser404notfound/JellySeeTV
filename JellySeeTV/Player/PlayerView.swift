import SwiftUI
import AetherEngine

// MARK: - Player Launcher (UIKit modal presentation)

/// Presents PlayerHostController as a UIKit modal (NOT SwiftUI fullScreenCover).
///
/// On tvOS, SwiftUI's fullScreenCover intercepts the Menu button at the
/// presentation level — pressesBegan, .onExitCommand, and gesture recognizers
/// on child VCs never receive it. UIKit modals don't have this problem:
/// UITapGestureRecognizer for .menu on the presented VC's view works.
struct PlayerLauncher: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let item: JellyfinItem?
    let startFromBeginning: Bool
    let playbackService: JellyfinPlaybackServiceProtocol
    let userID: String
    let preferences: PlaybackPreferences
    var cachedPlaybackInfo: PlaybackInfoResponse?

    func makeUIViewController(context: Context) -> PlayerLauncherHostVC {
        PlayerLauncherHostVC()
    }

    func updateUIViewController(_ host: PlayerLauncherHostVC, context: Context) {
        if isPresented, let item, host.presentedViewController == nil {
            let vm = PlayerViewModel(
                item: item,
                startFromBeginning: startFromBeginning,
                playbackService: playbackService,
                userID: userID,
                preferences: preferences,
                cachedPlaybackInfo: cachedPlaybackInfo
            )
            let playerVC = PlayerHostController(viewModel: vm, onDismiss: {
                host.dismiss(animated: false) {
                    isPresented = false
                }
            })
            playerVC.modalPresentationStyle = .fullScreen
            host.present(playerVC, animated: false)
        } else if !isPresented, host.presentedViewController != nil {
            host.dismiss(animated: false)
        }
    }
}

/// Invisible host VC for PlayerLauncher. Only purpose: be in the
/// window hierarchy so UIKit present() works. Focus restoration is
/// handled by SwiftUI's @FocusState in the detail views.
final class PlayerLauncherHostVC: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
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

    private var hasLaunched = false

    /// Tracks the currently hosted video layer. AetherEngine can replace
    /// the underlying layer on every load() (see its
    /// `onVideoLayerReplaced` callback and the "undefined behavior"
    /// warnings in SampleBufferRenderer). When that happens we need to
    /// pull the old sublayer out of our view hierarchy and drop the new
    /// one in — otherwise the host view keeps pointing at a stale layer
    /// that AetherEngine no longer feeds.
    private var hostedVideoLayer: CALayer?

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
        let layer = viewModel.player.videoLayer
        view.layer.addSublayer(layer)
        hostedVideoLayer = layer

        // Swap the sublayer if the engine recreates its video layer
        // (happens on every load() to avoid stale state from the
        // previous session). Without this the view keeps the old,
        // unfed layer and the user sees a frozen or black picture.
        viewModel.player.onVideoLayerReplaced = { [weak self] newLayer in
            Task { @MainActor in
                self?.swapVideoLayer(to: newLayer)
            }
        }

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

        // Background → engine stops demux loop (VT + AVIO die in suspension)
        // Foreground → reload pipeline at current position
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Kick off playback as the modal *starts* appearing instead of
        // waiting for the appear animation to fully complete. The
        // present() call uses animated:false so the gap is small, but
        // every ms of network/demuxer work that overlaps with the
        // present-then-layout sequence is one ms the user doesn't
        // wait at the end.
        guard !hasLaunched else { return }
        hasLaunched = true
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
        hostedVideoLayer?.frame = view.bounds
        CATransaction.commit()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Only stop playback if the VC is actually being dismissed.
        // Display mode switches (HDR/SDR) briefly trigger viewWillDisappear
        // without actually dismissing — don't kill playback for that.
        guard isBeingDismissed || isMovingFromParent else { return }
        hostedVideoLayer?.removeFromSuperlayer()
        viewModel.player.onVideoLayerReplaced = nil
        Task { await viewModel.stopPlayback() }
    }

    private func swapVideoLayer(to newLayer: CALayer) {
        hostedVideoLayer?.removeFromSuperlayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        newLayer.frame = view.bounds
        view.layer.insertSublayer(newLayer, at: 0)
        CATransaction.commit()
        hostedVideoLayer = newLayer
    }

    @objc private func appDidBecomeActive() {
        // AetherEngine stops the demux loop on didEnterBackground (VT sessions
        // and AVIO connections are invalidated by tvOS). Reload the pipeline
        // from the current position to rebuild everything safely.
        guard viewModel.hasStartedPlaying else { return }
        Task {
            try? await viewModel.player.reloadAtCurrentPosition()
        }
    }

    // MARK: - Press Handlers (state machine)

    @objc private func selectPressed() {
        // Next-episode and Skip-Intro commandeer Select only when the
        // transport is hidden — otherwise the user is interacting with
        // the control overlay (scrubbing, picking a track) and a
        // surprise skip/next would be destructive.
        if !viewModel.showControls && !viewModel.isDropdownOpen {
            if viewModel.showNextEpisodeOverlay {
                Task { await viewModel.playNextEpisode() }
                return
            }
            if viewModel.isInsideIntro {
                viewModel.skipIntro()
                return
            }
        }
        if viewModel.isDropdownOpen {
            confirmDropdownSelection()
        } else if viewModel.showControls && viewModel.controlsFocus != .progressBar {
            switch viewModel.controlsFocus {
            case .skipIntroButton: viewModel.skipIntro()
            case .audioButton: openAudioDropdown()
            case .subtitleButton: openSubtitleDropdown()
            case .speedButton: openSpeedDropdown()
            default: break
            }
        } else if viewModel.isScrubbing {
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
        // Cancelling the next-episode countdown only hijacks Menu when
        // the transport is hidden. With controls open, Menu behaves
        // normally (close dropdown → abort scrub → step focus → hide
        // controls) and the countdown keeps running in the corner.
        if viewModel.showNextEpisodeOverlay && !viewModel.showControls && !viewModel.isDropdownOpen {
            viewModel.cancelNextEpisode()
            return
        }
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
        if viewModel.showControls && viewModel.controlsFocus != .progressBar {
            stepTransportFocus(direction: -1)
        } else {
            viewModel.seekJumpByConfiguredInterval(direction: -1)
        }
    }

    @objc private func rightPressed() {
        if viewModel.isDropdownOpen { return }
        if viewModel.showControls && viewModel.controlsFocus != .progressBar {
            stepTransportFocus(direction: 1)
        } else {
            viewModel.seekJumpByConfiguredInterval(direction: 1)
        }
    }

    /// Move focus one step through the available transport buttons.
    /// Builds the list dynamically so a stream without audio or subtitle
    /// tracks still leaves speed reachable without dead stops.
    private func stepTransportFocus(direction: Int) {
        var order: [PlayerViewModel.ControlsFocus] = []
        if viewModel.isInsideIntro { order.append(.skipIntroButton) }
        if !viewModel.player.audioTracks.isEmpty { order.append(.audioButton) }
        if !viewModel.subtitleStreams.isEmpty { order.append(.subtitleButton) }
        order.append(.speedButton)
        guard let current = order.firstIndex(of: viewModel.controlsFocus) else { return }
        let next = current + direction
        if next >= 0 && next < order.count {
            viewModel.controlsFocus = order[next]
        }
    }

    @objc private func upPressed() {
        if viewModel.isDropdownOpen {
            moveDropdownHighlight(by: -1)
        } else if viewModel.showControls {
            switch viewModel.controlsFocus {
            case .progressBar:
                // Preserve scrub state — user can confirm/cancel when returning
                let hasAudio = !viewModel.player.audioTracks.isEmpty
                let hasSubs = !viewModel.subtitleStreams.isEmpty
                if viewModel.isInsideIntro { viewModel.controlsFocus = .skipIntroButton }
                else if hasAudio { viewModel.controlsFocus = .audioButton }
                else if hasSubs { viewModel.controlsFocus = .subtitleButton }
                else { viewModel.controlsFocus = .speedButton }
            case .skipIntroButton, .audioButton, .subtitleButton, .speedButton:
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
        // Items: Off (index 0), then each subtitle stream (index 1...)
        let currentIdx: Int
        if let activeId = viewModel.activeSubtitleIndex,
           let streamIdx = viewModel.subtitleStreams.firstIndex(where: { $0.index == activeId }) {
            currentIdx = streamIdx + 1
        } else {
            currentIdx = 0
        }
        viewModel.trackDropdown = .subtitle(highlighted: currentIdx)
    }

    private func openSpeedDropdown() {
        viewModel.controlsTimer?.cancel()
        viewModel.trackDropdown = .speed(highlighted: viewModel.activeSpeedIndex)
    }

    private func moveDropdownHighlight(by offset: Int) {
        switch viewModel.trackDropdown {
        case .audio(let idx):
            let count = viewModel.player.audioTracks.count
            guard count > 0 else { return }
            let newIdx = max(0, min(count - 1, idx + offset))
            viewModel.trackDropdown = .audio(highlighted: newIdx)
        case .subtitle(let idx):
            let count = viewModel.subtitleStreams.count + 1 // +1 for "Off"
            guard count > 0 else { return }
            let newIdx = max(0, min(count - 1, idx + offset))
            viewModel.trackDropdown = .subtitle(highlighted: newIdx)
        case .speed(let idx):
            let count = PlayerViewModel.speedOptions.count
            let newIdx = max(0, min(count - 1, idx + offset))
            viewModel.trackDropdown = .speed(highlighted: newIdx)
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
                let streams = viewModel.subtitleStreams
                let streamIdx = idx - 1
                if streamIdx < streams.count {
                    viewModel.selectSubtitleTrack(id: streams[streamIdx].index)
                }
            }
            viewModel.trackDropdown = .none
            viewModel.scheduleControlsHide()
        case .speed(let idx):
            viewModel.selectSpeed(index: idx)
            viewModel.trackDropdown = .none
            viewModel.scheduleControlsHide()
        case .none:
            break
        }
    }

    private func dismissPlayer() {
        hostedVideoLayer?.removeFromSuperlayer()
        viewModel.player.onVideoLayerReplaced = nil
        viewModel.resetDisplayCriteria()
        Task {
            await viewModel.stopPlayback()
            onDismiss()
        }
    }

    // MARK: - Pan (Touchpad Scrubbing)

    private var lastDropdownStep: CGFloat = 0

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if viewModel.isDropdownOpen {
            // Vertical swipe navigates dropdown items.
            // Uses total translation divided into steps — each 80pt of
            // cumulative movement = one item. Prevents over-scrolling
            // on fast swipes.
            switch gesture.state {
            case .began:
                lastDropdownStep = 0
            case .changed:
                let ty = gesture.translation(in: view).y
                let stepSize: CGFloat = 120
                let currentStep = (ty / stepSize).rounded(.towardZero)
                if currentStep != lastDropdownStep {
                    let steps = Int(currentStep - lastDropdownStep)
                    moveDropdownHighlight(by: steps)
                    lastDropdownStep = currentStep
                }
            case .ended, .cancelled:
                lastDropdownStep = 0
            default:
                break
            }
        } else {
            // Horizontal swipe scrubs timeline
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
}

// MARK: - Overlay View (display-only SwiftUI)

private struct PlayerOverlayView: View {
    let viewModel: PlayerViewModel

    var body: some View {
        ZStack {
            if !viewModel.subtitleCues.isEmpty {
                SubtitleOverlayView(
                    cues: viewModel.subtitleCues,
                    currentTime: viewModel.playbackTime
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

            // Floating Skip Intro hint — only while the full controls
            // are hidden. When they open, the skip action becomes a
            // proper focusable button inside TransportBar instead.
            if viewModel.isInsideIntro
                && !viewModel.showControls
                && viewModel.errorMessage == nil
                && !viewModel.showNextEpisodeOverlay {
                introSkipOverlay
            }

            // Next episode overlay
            if viewModel.showNextEpisodeOverlay,
               let next = viewModel.nextEpisode {
                nextEpisodeOverlay(next)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showNextEpisodeOverlay)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isInsideIntro)
    }

    private var introSkipOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "forward.end.fill")
                        .font(.body)
                    Text(String(localized: "player.skipIntro", defaultValue: "Skip Intro"))
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .padding(.trailing, 80)
                .padding(.bottom, 80)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    private func nextEpisodeOverlay(_ episode: JellyfinItem) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                cardBody(for: episode)
                    .padding(.trailing, viewModel.showControls ? 60 : 40)
                    .padding(.bottom, viewModel.showControls ? 300 : 40)
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func cardBody(for episode: JellyfinItem) -> some View {
        ZStack {
            // Backdrop: episode thumbnail, dimmed so the text on top
            // stays legible. Sits as a layer inside the ZStack rather
            // than as a `.background()` modifier so it actually fills
            // the card frame (a `.background()` AsyncImage gets
            // proposed an intrinsic size of zero and never appears).
            if let imageURL = episodeThumbnailURL(for: episode) {
                AsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .opacity(0.4)
            }

            // Foreground text content.
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "player.nextEpisode", defaultValue: "Next Episode"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let s = episode.parentIndexNumber, let e = episode.indexNumber {
                        Text("S\(s)E\(e)")
                            .foregroundStyle(.white.opacity(0.85))
                            .layoutPriority(1)
                    }
                    Text(episode.name)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .font(.body)
                .fontWeight(.semibold)

                if viewModel.isCountdownActive, viewModel.nextEpisodeCountdown > 0 {
                    Text("player.nextEpisode.countdown \(viewModel.nextEpisodeCountdown)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 380 × 214 = 16:9 baseline matching the Jellyfin thumbnail
        // aspect. minHeight (not fixed height) so an extreme title can
        // grow the card vertically instead of clipping.
        .frame(width: 380)
        .frame(minHeight: 214)
        // thinMaterial UNDER the ZStack so the image floats on top of
        // the glass blur but text floats above the image.
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    /// Build episode thumbnail URL directly from item data
    /// (avoids needing JellyfinImageService in the player).
    private func episodeThumbnailURL(for item: JellyfinItem) -> URL? {
        guard let baseURL = viewModel.playbackService.baseURL else { return nil }
        if let tag = item.imageTags?.primary {
            return URL(string: "\(baseURL)/Items/\(item.id)/Images/Primary?tag=\(tag)&maxWidth=640&quality=80")
        }
        if let tags = item.backdropImageTags, let tag = tags.first {
            return URL(string: "\(baseURL)/Items/\(item.id)/Images/Backdrop?tag=\(tag)&maxWidth=640&quality=80")
        }
        if let tags = item.parentBackdropImageTags, let tag = tags.first, let seriesId = item.seriesId {
            return URL(string: "\(baseURL)/Items/\(seriesId)/Images/Backdrop?tag=\(tag)&maxWidth=640&quality=80")
        }
        return nil
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

            // Title (top left) + HDR badge (top right)
            VStack {
                HStack(alignment: .top) {
                    PlayerTitleOverlay(item: viewModel.item)
                    Spacer()
                    if viewModel.videoFormat != .sdr {
                        VideoFormatBadge(format: viewModel.videoFormat)
                            .padding(.horizontal, 80)
                            .padding(.top, 68)
                    }
                }
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
                    subtitleStreams: viewModel.subtitleStreams,
                    activeAudioIndex: viewModel.activeAudioIndex,
                    activeSubtitleIndex: viewModel.activeSubtitleIndex,
                    activeSpeedIndex: viewModel.activeSpeedIndex,
                    controlsFocus: viewModel.controlsFocus,
                    trackDropdown: viewModel.trackDropdown,
                    showSkipIntroButton: viewModel.isInsideIntro
                )
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Video Format Badge

private struct VideoFormatBadge: View {
    let format: VideoFormat

    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
    }

    private var label: String {
        switch format {
        case .sdr:          return "SDR"
        case .hdr10:        return "HDR10"
        case .dolbyVision:  return "Dolby Vision"
        case .hlg:          return "HLG"
        }
    }
}
