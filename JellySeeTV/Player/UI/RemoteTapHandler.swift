import SwiftUI

/// UIViewRepresentable that captures all Siri Remote input for the player.
///
/// Uses UITapGestureRecognizer with allowedPressTypes instead of
/// pressesBegan/pressesEnded. Gesture recognizers operate BEFORE the
/// tvOS focus engine — they fire without the view needing focus.
/// This fixes the "double-click required" issue where the first press
/// was consumed by the focus system instead of triggering the action.
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

/// UIView that handles all Siri Remote input via gesture recognizers.
///
/// Gesture recognizers fire independently of the tvOS focus system —
/// no need for the view to be focused or first responder. This is the
/// same mechanism that makes UIPanGestureRecognizer work for touchpad
/// scrubbing without focus.
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

    /// Prevent tvOS focus engine from interfering — this view handles
    /// input via gesture recognizers, not through the responder chain.
    override var canBecomeFocused: Bool { true }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        // No visual focus effect — invisible input handler
    }

    // MARK: - Gesture Recognizer Setup

    func setupGestureRecognizers() {
        addPressGesture(.select, action: #selector(handleSelect))
        addPressGesture(.playPause, action: #selector(handlePlayPause))
        addPressGesture(.menu, action: #selector(handleMenu))
        addPressGesture(.leftArrow, action: #selector(handleLeftArrow))
        addPressGesture(.rightArrow, action: #selector(handleRightArrow))
        addPressGesture(.upArrow, action: #selector(handleUpArrow))
        addPressGesture(.downArrow, action: #selector(handleDownArrow))

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        addGestureRecognizer(pan)
    }

    private func addPressGesture(_ pressType: UIPress.PressType, action: Selector) {
        let tap = UITapGestureRecognizer(target: self, action: action)
        tap.allowedPressTypes = [NSNumber(value: pressType.rawValue)]
        addGestureRecognizer(tap)
    }

    // MARK: - Press Handlers

    @objc private func handleSelect() { onTap?() }
    @objc private func handlePlayPause() { onPlayPause?() }
    @objc private func handleMenu() { onMenu?() }
    @objc private func handleLeftArrow() { onLeft?() }
    @objc private func handleRightArrow() { onRight?() }
    @objc private func handleUpArrow() { onUp?() }
    @objc private func handleDownArrow() { onDown?() }

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
