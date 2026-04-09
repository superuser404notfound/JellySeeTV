import SwiftUI
import AVFoundation

/// UIViewRepresentable that hosts an AVSampleBufferDisplayLayer for video rendering.
struct VideoLayerView: UIViewRepresentable {
    let renderer: VideoRenderer

    func makeUIView(context: Context) -> VideoDisplayUIView {
        let view = VideoDisplayUIView()
        view.backgroundColor = .black
        // Add the display layer
        view.layer.addSublayer(renderer.displayLayer)
        return view
    }

    func updateUIView(_ uiView: VideoDisplayUIView, context: Context) {
        // Update layer frame if needed
        renderer.displayLayer.frame = uiView.bounds
    }
}

/// UIView subclass that keeps the display layer sized correctly
class VideoDisplayUIView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        // Resize all sublayers to fill the view
        layer.sublayers?.forEach { sublayer in
            if sublayer is AVSampleBufferDisplayLayer {
                sublayer.frame = bounds
            }
        }
    }

    override var canBecomeFocused: Bool { false }
}
