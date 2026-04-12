import SwiftUI
import UIKit
import QuartzCore

/// UIViewRepresentable that hosts SteelPlayer's CAMetalLayer.
struct SteelPlayerVideoView: UIViewRepresentable {
    let metalLayer: CAMetalLayer

    func makeUIView(context: Context) -> MetalLayerHostView {
        MetalLayerHostView(metalLayer: metalLayer)
    }

    func updateUIView(_ uiView: MetalLayerHostView, context: Context) {
        uiView.refreshDrawableSize()
    }
}

/// UIView that hosts a CAMetalLayer and keeps its frame + drawableSize
/// synchronized with the view bounds.
final class MetalLayerHostView: UIView {
    private let metalLayer: CAMetalLayer

    init(metalLayer: CAMetalLayer) {
        self.metalLayer = metalLayer
        super.init(frame: .zero)
        layer.addSublayer(metalLayer)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshDrawableSize()
    }

    func refreshDrawableSize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = bounds
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        CATransaction.commit()
    }

    override var canBecomeFocused: Bool { false }
}
