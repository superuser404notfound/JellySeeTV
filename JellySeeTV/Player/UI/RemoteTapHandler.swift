import SwiftUI

/// UIViewRepresentable that captures Siri Remote touchpad pan gestures.
///
/// Only handles pan gestures — all button presses (Select, Menu,
/// Play/Pause, arrows) are handled by SwiftUI modifiers (.onMoveCommand,
/// .onExitCommand, .onPlayPauseCommand, Button action) because tvOS
/// doesn't deliver Select/Menu to UIKit gesture recognizers reliably.
///
/// Indirect touchpad touches work without focus (different from button
/// presses), so UIPanGestureRecognizer fires immediately.
struct PanGestureView: UIViewRepresentable {
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    func makeUIView(context: Context) -> PanInputView {
        let view = PanInputView()
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded

        let pan = UIPanGestureRecognizer(target: view, action: #selector(PanInputView.handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: PanInputView, context: Context) {
        uiView.onPanChanged = onPanChanged
        uiView.onPanEnded = onPanEnded
    }
}

class PanInputView: UIView {
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    // Don't participate in focus system — SwiftUI handles focus
    override var canBecomeFocused: Bool { false }

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
