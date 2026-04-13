import SwiftUI

/// UIViewRepresentable that captures all Siri Remote input for the player.
///
/// Press gesture recognizers are attached to the UIWindow (not the view)
/// because tvOS only delivers press events to the focused view, and
/// UIHostingController doesn't reliably propagate focus to
/// UIViewRepresentable subviews. The window always receives events.
///
/// Pan gesture stays on the view — indirect touchpad touches work
/// without focus (proven by scrubbing always working).
struct RemoteTapHandler: UIViewRepresentable {
    var onTap: () -> Void
    var onPlayPause: () -> Void
    var onMenu: () -> Void
    var onLeft: () -> Void
    var onRight: () -> Void
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    func makeUIView(context: Context) -> RemoteInputView {
        let view = RemoteInputView()
        applyCallbacks(to: view)
        return view
    }

    func updateUIView(_ uiView: RemoteInputView, context: Context) {
        applyCallbacks(to: uiView)
    }

    private func applyCallbacks(to view: RemoteInputView) {
        view.onTap = onTap
        view.onPlayPause = onPlayPause
        view.onMenu = onMenu
        view.onLeft = onLeft
        view.onRight = onRight
        view.onUp = onUp
        view.onDown = onDown
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
    }
}

/// UIView that handles all Siri Remote input.
///
/// Press gesture recognizers are on the window (focus-independent).
/// Pan gesture recognizer is on this view (touchpad works without focus).
class RemoteInputView: UIView {
    var onTap: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onMenu: (() -> Void)?
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    /// Gesture recognizers added to the window — must be cleaned up on removal.
    private var windowGestures: [UIGestureRecognizer] = []

    override func didMoveToWindow() {
        super.didMoveToWindow()

        // Clean up old window gestures
        for gr in windowGestures {
            gr.view?.removeGestureRecognizer(gr)
        }
        windowGestures.removeAll()

        guard let window else { return }

        #if DEBUG
        print("[Remote] didMoveToWindow, frame=\(frame)")
        #endif

        // Press gesture recognizers on the WINDOW — window receives press
        // events regardless of which view has focus. This bypasses the
        // UIHostingController focus propagation issue entirely.
        windowGestures.append(addWindowPress(window, .select, #selector(gestureSelect)))
        windowGestures.append(addWindowPress(window, .playPause, #selector(gesturePlayPause)))
        windowGestures.append(addWindowPress(window, .menu, #selector(gestureMenu)))
        windowGestures.append(addWindowPress(window, .leftArrow, #selector(gestureLeft)))
        windowGestures.append(addWindowPress(window, .rightArrow, #selector(gestureRight)))
        windowGestures.append(addWindowPress(window, .upArrow, #selector(gestureUp)))
        windowGestures.append(addWindowPress(window, .downArrow, #selector(gestureDown)))

        // Pan gesture on THIS view — indirect touchpad touches work without focus
        if gestureRecognizers?.isEmpty ?? true {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            addGestureRecognizer(pan)
        }
    }

    private func addWindowPress(_ window: UIWindow, _ type: UIPress.PressType, _ action: Selector) -> UIGestureRecognizer {
        let tap = UITapGestureRecognizer(target: self, action: action)
        tap.allowedPressTypes = [NSNumber(value: type.rawValue)]
        window.addGestureRecognizer(tap)
        return tap
    }

    deinit {
        for gr in windowGestures {
            gr.view?.removeGestureRecognizer(gr)
        }
    }

    // MARK: - Press Handlers

    @objc private func gestureSelect() {
        #if DEBUG
        print("[Remote] select")
        #endif
        onTap?()
    }
    @objc private func gesturePlayPause() {
        #if DEBUG
        print("[Remote] playPause")
        #endif
        onPlayPause?()
    }
    @objc private func gestureMenu() {
        #if DEBUG
        print("[Remote] menu")
        #endif
        onMenu?()
    }
    @objc private func gestureLeft() {
        #if DEBUG
        print("[Remote] left")
        #endif
        onLeft?()
    }
    @objc private func gestureRight() {
        #if DEBUG
        print("[Remote] right")
        #endif
        onRight?()
    }
    @objc private func gestureUp() {
        #if DEBUG
        print("[Remote] up")
        #endif
        onUp?()
    }
    @objc private func gestureDown() {
        #if DEBUG
        print("[Remote] down")
        #endif
        onDown?()
    }

    // MARK: - Pan (Touchpad Scrubbing)

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let width = max(bounds.width, 1)
            let normalized = gesture.translation(in: self).x / width
            onPanChanged?(normalized)
        case .ended, .cancelled:
            onPanEnded?()
        default:
            break
        }
    }
}
