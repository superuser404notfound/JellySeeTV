import SwiftUI
import UIKit

/// UIViewRepresentable that hosts the UIView VLC renders into.
/// VLC manages its own rendering pipeline (CoreVideo + VideoToolbox); we only
/// hand it a black UIView to draw inside.
struct VideoLayerView: UIViewRepresentable {
    let drawableView: UIView

    func makeUIView(context: Context) -> ContainerView {
        let container = ContainerView()
        container.backgroundColor = .black
        container.addSubview(drawableView)
        return container
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        // Layout happens in ContainerView.layoutSubviews
        uiView.setNeedsLayout()
    }
}

/// Container that keeps the VLC drawable view filling its bounds.
final class ContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        for sub in subviews {
            sub.frame = bounds
        }
    }

    override var canBecomeFocused: Bool { false }
}
