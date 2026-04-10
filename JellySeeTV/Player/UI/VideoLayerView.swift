import SwiftUI
import QuartzCore

/// UIViewRepresentable that hosts a CAMetalLayer for mpv to render into.
struct VideoLayerView: UIViewRepresentable {
    let metalLayer: CAMetalLayer

    func makeUIView(context: Context) -> MetalView {
        let view = MetalView(metalLayer: metalLayer)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: MetalView, context: Context) {
        uiView.updateLayerSize()
    }
}

/// UIView that hosts a CAMetalLayer and keeps its frame + drawableSize in sync.
class MetalView: UIView {
    let metalLayer: CAMetalLayer

    init(metalLayer: CAMetalLayer) {
        self.metalLayer = metalLayer
        super.init(frame: .zero)
        layer.addSublayer(metalLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateLayerSize() {
        guard bounds != .zero else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = bounds
        // drawableSize must be in PIXELS, not points
        let scale = window?.windowScene?.screen.scale ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerSize()
    }

    override var canBecomeFocused: Bool { false }
}
