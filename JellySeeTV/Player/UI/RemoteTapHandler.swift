import SwiftUI

/// UIViewRepresentable that captures Siri Remote input for the player.
///
/// On tvOS, SwiftUI command modifiers don't fire reliably when focus is on
/// a UIKit view, so we handle all press types and touchpad gestures here.
///
/// The `isActive` flag controls whether this view grabs focus. Set to false
/// when showing overlays (track selection) so SwiftUI buttons can receive focus.
struct RemoteTapHandler: UIViewRepresentable {
    var isActive: Bool = true
    var onTap: () -> Void
    var onPlayPause: () -> Void
    var onMenu: () -> Void
    var onLeft: () -> Void
    var onRight: () -> Void
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    func makeUIView(context: Context) -> RemoteInputView {
        let view = RemoteInputView()
        applyCallbacks(to: view)

        let pan = UIPanGestureRecognizer(target: view, action: #selector(RemoteInputView.handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: RemoteInputView, context: Context) {
        applyCallbacks(to: uiView)
        uiView.isInputActive = isActive

        if isActive {
            // Reclaim focus when re-activated
            uiView.setNeedsFocusUpdate()
            uiView.updateFocusIfNeeded()
        }
    }

    private func applyCallbacks(to view: RemoteInputView) {
        view.onTap = onTap
        view.onPlayPause = onPlayPause
        view.onMenu = onMenu
        view.onLeft = onLeft
        view.onRight = onRight
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
    }
}

/// UIView that handles all Siri Remote presses + touchpad pan gestures.
class RemoteInputView: UIView {
    var onTap: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onMenu: (() -> Void)?
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    /// When false, this view releases focus so SwiftUI views can receive it.
    var isInputActive = true

    override var canBecomeFocused: Bool { isInputActive }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, isInputActive else { return }
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        isInputActive ? [self] : []
    }

    // MARK: - Press Handling

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed = false
        for press in presses {
            switch press.type {
            case .select, .playPause, .menu, .leftArrow, .rightArrow:
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
                onTap?()
                consumed = true
            case .playPause:
                onPlayPause?()
                consumed = true
            case .menu:
                onMenu?()
                consumed = true
            case .leftArrow:
                onLeft?()
                consumed = true
            case .rightArrow:
                onRight?()
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

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
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
