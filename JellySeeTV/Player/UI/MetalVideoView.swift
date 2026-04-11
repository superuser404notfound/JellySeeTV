import SwiftUI
import UIKit
import QuartzCore

/// SwiftUI wrapper around a UIView that hosts a `CAMetalLayer`. The
/// MetalHDRRenderer owns the layer; we just attach it to the view
/// hierarchy and keep its `drawableSize` in sync with the view bounds.
struct MetalVideoView: UIViewRepresentable {
    let metalLayer: CAMetalLayer

    func makeUIView(context: Context) -> MetalLayerHostView {
        let view = MetalLayerHostView(metalLayer: metalLayer)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: MetalLayerHostView, context: Context) {
        uiView.refreshDrawableSize()
    }
}

/// UIView that hosts a CAMetalLayer as a sublayer. Keeps the layer's
/// frame and `drawableSize` in sync with the view's bounds (drawableSize
/// has to be specified in pixels, not points).
final class MetalLayerHostView: UIView {
    private let metalLayer: CAMetalLayer

    init(metalLayer: CAMetalLayer) {
        self.metalLayer = metalLayer
        super.init(frame: .zero)
        layer.addSublayer(metalLayer)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshDrawableSize()
    }

    /// Update the metal layer's frame + drawableSize. Drawable size must
    /// be in pixels, so we multiply by the screen's contentsScale.
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
