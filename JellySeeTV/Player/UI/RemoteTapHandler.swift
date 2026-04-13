import SwiftUI

/// UIViewRepresentable that captures all Siri Remote input for the player.
///
/// Uses TWO mechanisms for maximum reliability:
/// 1. UITapGestureRecognizer with allowedPressTypes (focus-independent)
/// 2. pressesBegan/pressesEnded as fallback (focus-dependent)
///
/// Gesture recognizers should fire first. If they don't (e.g. before
/// the view has focus), pressesBegan catches it once focus is acquired.
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
        view.setupGestureRecognizers()
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

    override var canBecomeFocused: Bool { true }
    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [self] }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        #if DEBUG
        if context.nextFocusedView === self {
            print("[Remote] ✓ Gained focus")
        } else if context.previouslyFocusedView === self {
            print("[Remote] ✗ Lost focus")
        }
        #endif
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        #if DEBUG
        print("[Remote] didMoveToWindow, window=\(window != nil), frame=\(frame)")
        #endif
    }

    // MARK: - Gesture Recognizer Setup (focus-independent)

    func setupGestureRecognizers() {
        addPressGesture(.select, action: #selector(gestureSelect))
        addPressGesture(.playPause, action: #selector(gesturePlayPause))
        addPressGesture(.menu, action: #selector(gestureMenu))
        addPressGesture(.leftArrow, action: #selector(gestureLeft))
        addPressGesture(.rightArrow, action: #selector(gestureRight))
        addPressGesture(.upArrow, action: #selector(gestureUp))
        addPressGesture(.downArrow, action: #selector(gestureDown))

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        addGestureRecognizer(pan)
    }

    private func addPressGesture(_ pressType: UIPress.PressType, action: Selector) {
        let tap = UITapGestureRecognizer(target: self, action: action)
        tap.allowedPressTypes = [NSNumber(value: pressType.rawValue)]
        addGestureRecognizer(tap)
    }

    // MARK: - Gesture Handlers

    @objc private func gestureSelect() {
        #if DEBUG
        print("[Remote] GR: select")
        #endif
        onTap?()
    }
    @objc private func gesturePlayPause() {
        #if DEBUG
        print("[Remote] GR: playPause")
        #endif
        onPlayPause?()
    }
    @objc private func gestureMenu() {
        #if DEBUG
        print("[Remote] GR: menu")
        #endif
        onMenu?()
    }
    @objc private func gestureLeft() {
        #if DEBUG
        print("[Remote] GR: left")
        #endif
        onLeft?()
    }
    @objc private func gestureRight() {
        #if DEBUG
        print("[Remote] GR: right")
        #endif
        onRight?()
    }
    @objc private func gestureUp() {
        #if DEBUG
        print("[Remote] GR: up")
        #endif
        onUp?()
    }
    @objc private func gestureDown() {
        #if DEBUG
        print("[Remote] GR: down")
        #endif
        onDown?()
    }

    // MARK: - Press Handling (fallback, requires focus)

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed = false
        for press in presses {
            switch press.type {
            case .select, .playPause, .menu, .leftArrow, .rightArrow, .upArrow, .downArrow:
                consumed = true
            default:
                break
            }
        }
        if !consumed {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed = false
        for press in presses {
            switch press.type {
            case .select:
                #if DEBUG
                print("[Remote] PE: select")
                #endif
                onTap?()
                consumed = true
            case .playPause:
                #if DEBUG
                print("[Remote] PE: playPause")
                #endif
                onPlayPause?()
                consumed = true
            case .menu:
                #if DEBUG
                print("[Remote] PE: menu")
                #endif
                onMenu?()
                consumed = true
            case .leftArrow:
                #if DEBUG
                print("[Remote] PE: left")
                #endif
                onLeft?()
                consumed = true
            case .rightArrow:
                #if DEBUG
                print("[Remote] PE: right")
                #endif
                onRight?()
                consumed = true
            case .upArrow:
                #if DEBUG
                print("[Remote] PE: up")
                #endif
                onUp?()
                consumed = true
            case .downArrow:
                #if DEBUG
                print("[Remote] PE: down")
                #endif
                onDown?()
                consumed = true
            default:
                break
            }
        }
        if !consumed {
            super.pressesEnded(presses, with: event)
        }
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
