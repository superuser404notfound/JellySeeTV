import SwiftUI
import UIKit
import QuartzCore

/// UIViewRepresentable that hosts SteelPlayer's video layer.
struct SteelPlayerVideoView: UIViewRepresentable {
    let videoLayer: CALayer

    func makeUIView(context: Context) -> VideoLayerHostView {
        VideoLayerHostView(videoLayer: videoLayer)
    }

    func updateUIView(_ uiView: VideoLayerHostView, context: Context) {
        uiView.refreshLayout()
    }
}

/// UIView that hosts the video layer and keeps its frame
/// synchronized with the view bounds.
final class VideoLayerHostView: UIView {
    private let videoLayer: CALayer

    init(videoLayer: CALayer) {
        self.videoLayer = videoLayer
        super.init(frame: .zero)
        layer.addSublayer(videoLayer)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshLayout()
    }

    func refreshLayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }

    override var canBecomeFocused: Bool { false }
}
