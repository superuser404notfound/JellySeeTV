import SwiftUI

/// UIViewRepresentable that captures Siri Remote input for the player.
/// Handles: clickpad tap, touch surface pan (scrubbing).
/// Must be the focused view to receive events on tvOS.
struct RemoteTapHandler: UIViewRepresentable {
    var onTap: () -> Void
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RemoteInputView {
        let view = RemoteInputView()
        let coord = context.coordinator
        coord.onTap = onTap
        coord.onPanChanged = onPanChanged
        coord.onPanEnded = onPanEnded

        // Pan on touch surface for scrubbing
        let pan = UIPanGestureRecognizer(target: coord, action: #selector(Coordinator.handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: RemoteInputView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onPanChanged = onPanChanged
        context.coordinator.onPanEnded = onPanEnded
    }

    class Coordinator: NSObject {
        var onTap: (() -> Void)?
        var onPanChanged: ((CGFloat) -> Void)?
        var onPanEnded: (() -> Void)?

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .changed:
                let translation = gesture.translation(in: view)
                let normalized = translation.x / 1920.0
                onPanChanged?(normalized)
            case .ended, .cancelled:
                onPanEnded?()
            default:
                break
            }
        }
    }
}

/// UIView that grabs focus and handles the select press (clickpad tap).
/// Uses pressesBegan/pressesEnded instead of UITapGestureRecognizer for
/// more reliable detection on tvOS.
class RemoteInputView: UIView {
    weak var coordinator: RemoteTapHandler.Coordinator?

    override var canBecomeFocused: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async {
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Only handle select (clickpad) press
        guard presses.contains(where: { $0.type == .select }) else {
            super.pressesBegan(presses, with: event)
            return
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            coordinator?.onTap?()
        } else {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesCancelled(presses, with: event)
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [self] }
}
