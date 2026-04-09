import SwiftUI
import TVVLCKit

struct VLCPlayerWrapper: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> VLCVideoUIView {
        let view = VLCVideoUIView(player: player)
        return view
    }

    func updateUIView(_ uiView: VLCVideoUIView, context: Context) {
        // Player is managed externally
    }
}

/// Custom UIView that properly connects VLCMediaPlayer drawable
/// after the view is in the window hierarchy.
class VLCVideoUIView: UIView {
    private let player: VLCMediaPlayer

    init(player: VLCMediaPlayer) {
        self.player = player
        super.init(frame: .zero)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            // View is now in the hierarchy -- safe to set drawable
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.player.drawable = self
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure VLC video fills the entire view
        for subview in subviews {
            subview.frame = bounds
        }
    }
}
