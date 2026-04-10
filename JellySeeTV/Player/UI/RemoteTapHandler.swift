import SwiftUI

/// UIViewRepresentable that captures ALL Siri Remote input for the player.
/// SwiftUI command modifiers don't fire when focus is on a UIKit view, so we
/// handle every press type here and forward via callbacks.
struct RemoteTapHandler: UIViewRepresentable {
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

/// UIView that grabs focus and handles all Siri Remote presses + touch surface pan.
class RemoteInputView: UIView {
    var onTap: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onMenu: (() -> Void)?
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
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

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Claim known presses so they don't propagate as system back/etc
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
                print("[RemoteInputView] SELECT → tap")
                #endif
                onTap?()
                consumed = true
            case .playPause:
                #if DEBUG
                print("[RemoteInputView] PLAY/PAUSE")
                #endif
                onPlayPause?()
                consumed = true
            case .menu:
                #if DEBUG
                print("[RemoteInputView] MENU")
                #endif
                onMenu?()
                consumed = true
            case .leftArrow:
                #if DEBUG
                print("[RemoteInputView] LEFT")
                #endif
                onLeft?()
                consumed = true
            case .rightArrow:
                #if DEBUG
                print("[RemoteInputView] RIGHT")
                #endif
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

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            #if DEBUG
            print("[RemoteInputView] Pan began")
            #endif
        case .changed:
            let translation = gesture.translation(in: self)
            let normalized = translation.x / 1920.0
            #if DEBUG
            // Only log occasional updates to avoid spam
            if Int.random(in: 0..<20) == 0 {
                print("[RemoteInputView] Pan changed: \(String(format: "%.3f", normalized))")
            }
            #endif
            onPanChanged?(normalized)
        case .ended, .cancelled:
            #if DEBUG
            print("[RemoteInputView] Pan ended")
            #endif
            onPanEnded?()
        default:
            break
        }
    }
}
