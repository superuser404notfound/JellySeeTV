import SwiftUI

/// UIViewRepresentable that captures all Siri Remote input for the player.
///
/// On tvOS, SwiftUI command modifiers (.onExitCommand, .onPlayPauseCommand)
/// conflict with UIKit focus when both systems are used simultaneously.
/// This handler captures ALL remote input via UIKit, avoiding focus issues.
///
/// Always active — callbacks are state-aware and decide behavior based on
/// player state (controls hidden/visible, scrubbing, etc).
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

        let pan = UIPanGestureRecognizer(target: view, action: #selector(RemoteInputView.handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: RemoteInputView, context: Context) {
        applyCallbacks(to: uiView)
        // Reclaim focus after view hierarchy changes (e.g. loading overlay
        // removed). Async ensures SwiftUI has finished its layout pass.
        // No-op if already focused.
        DispatchQueue.main.async {
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
        view.onUp = onUp
        view.onDown = onDown
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
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    override var canBecomeFocused: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [self] }

    // MARK: - Press Handling

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
            case .upArrow:
                onUp?()
                consumed = true
            case .downArrow:
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
