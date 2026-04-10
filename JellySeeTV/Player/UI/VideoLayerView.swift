import SwiftUI
import UIKit

/// UIViewRepresentable that hosts the UIView VLC renders into.
///
/// VLCKit on tvOS uses an OpenGLES2-backed video view that misbehaves badly
/// if the host view's frame changes via direct .frame assignment from
/// layoutSubviews — VLC's render thread tries to mutate layer properties
/// off-main, which on modern UIKit results in a stuck render pipeline.
///
/// Pattern (matches Swiftfin / VLCUI):
///   ContainerView    ← what SwiftUI hosts
///     └── contentView ← VLC drawable, sized via Auto Layout constraints
struct VideoLayerView: UIViewRepresentable {
    let engine: VLCPlayerEngine

    func makeUIView(context: Context) -> VLCContainerView {
        let container = VLCContainerView()
        // Hand the VLC-drawable subview to the engine *after* it's in a
        // view hierarchy with non-zero bounds-track from Auto Layout.
        engine.attachDrawable(container.contentView)
        return container
    }

    func updateUIView(_ uiView: VLCContainerView, context: Context) {
        // Auto Layout handles resizes; nothing to do here.
    }
}

/// Container UIView that owns the VLC drawable as a constraint-pinned subview.
final class VLCContainerView: UIView {
    let contentView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var canBecomeFocused: Bool { false }
}
