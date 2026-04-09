import SwiftUI

/// Callbacks for Siri Remote interactions.
struct RemoteActions {
    let onTap: () -> Void
    let onSwipe: ((_ direction: SwipeDirection, _ velocity: CGFloat) -> Void)?
    let onPanChanged: ((_ translation: CGFloat) -> Void)?
    let onPanEnded: (() -> Void)?

    enum SwipeDirection {
        case left, right
    }
}

/// UIViewRepresentable that detects taps, swipes, and pans on the Siri Remote.
struct RemoteTapHandler: UIViewRepresentable {
    let actions: RemoteActions

    init(onTap: @escaping () -> Void,
         onSwipe: ((_ direction: RemoteActions.SwipeDirection, _ velocity: CGFloat) -> Void)? = nil,
         onPanChanged: ((_ translation: CGFloat) -> Void)? = nil,
         onPanEnded: (() -> Void)? = nil) {
        self.actions = RemoteActions(
            onTap: onTap,
            onSwipe: onSwipe,
            onPanChanged: onPanChanged,
            onPanEnded: onPanEnded
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions)
    }

    func makeUIView(context: Context) -> RemoteTapUIView {
        let view = RemoteTapUIView()
        view.coordinator = context.coordinator

        // Tap (select press)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(tap)

        // Pan for scrubbing on touch surface
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)

        // Swipe left
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        // Swipe right
        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)

        // Let pan and swipe coexist
        pan.require(toFail: swipeLeft)
        pan.require(toFail: swipeRight)

        return view
    }

    func updateUIView(_ uiView: RemoteTapUIView, context: Context) {
        context.coordinator.actions = actions
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var actions: RemoteActions
        private var panStartX: CGFloat = 0

        init(actions: RemoteActions) {
            self.actions = actions
        }

        @objc func handleTap() {
            actions.onTap()
        }

        @objc func handleSwipeLeft() {
            actions.onSwipe?(.left, 1.0)
        }

        @objc func handleSwipeRight() {
            actions.onSwipe?(.right, 1.0)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                panStartX = 0
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                // Normalize: touch surface is ~1920 logical points on tvOS
                let normalizedX = translation.x / 1920.0
                actions.onPanChanged?(normalizedX)
            case .ended, .cancelled:
                actions.onPanEnded?()
            default:
                break
            }
        }
    }
}

/// UIView that can become focused to receive remote events.
class RemoteTapUIView: UIView {
    weak var coordinator: RemoteTapHandler.Coordinator?
    override var canBecomeFocused: Bool { true }
}
