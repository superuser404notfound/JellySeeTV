import SwiftUI

/// UIViewRepresentable that captures Siri Remote input.
/// Uses pressesEnded for click detection and UIPanGestureRecognizer for scrubbing.
struct RemoteTapHandler: UIViewRepresentable {
    var onTap: () -> Void
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    func makeUIView(context: Context) -> RemoteInputView {
        let view = RemoteInputView()
        view.onTap = onTap
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded

        // Pan on touch surface (indirect touches = Siri Remote glass)
        let pan = UIPanGestureRecognizer(target: view, action: #selector(RemoteInputView.handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: RemoteInputView, context: Context) {
        uiView.onTap = onTap
        uiView.onPanChanged = onPanChanged
        uiView.onPanEnded = onPanEnded
    }
}

/// UIView that becomes focused to receive Siri Remote events.
class RemoteInputView: UIView {
    var onTap: (() -> Void)?
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    override var canBecomeFocused: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // Force focus on next runloop tick
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setNeedsFocusUpdate()
            self.updateFocusIfNeeded()
            #if DEBUG
            print("[RemoteInputView] Focus requested, isFocused: \(self.isFocused)")
            #endif
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        #if DEBUG
        print("[RemoteInputView] Focus changed: nextFocused=\(context.nextFocusedView == self)")
        #endif
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses where press.type == .select {
            #if DEBUG
            print("[RemoteInputView] SELECT press → onTap")
            #endif
            onTap?()
            handled = true
        }
        if !handled {
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
