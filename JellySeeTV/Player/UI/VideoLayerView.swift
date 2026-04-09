import SwiftUI

/// UIViewRepresentable that hosts the video renderer's CALayer.
struct VideoLayerView: UIViewRepresentable {
    let renderer: VideoRenderer

    func makeUIView(context: Context) -> VideoDisplayUIView {
        let view = VideoDisplayUIView(displayLayer: renderer.displayLayer)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: VideoDisplayUIView, context: Context) {
        uiView.updateLayerFrame()
    }
}

/// UIView subclass that keeps the display layer sized correctly.
class VideoDisplayUIView: UIView {
    private let displayLayer: CALayer

    init(displayLayer: CALayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateLayerFrame() {
        guard displayLayer.frame != bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerFrame()
    }

    override var canBecomeFocused: Bool { false }
}
