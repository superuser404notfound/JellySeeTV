import SwiftUI

/// UIViewRepresentable that detects taps and presses on the Siri Remote touch surface.
/// SwiftUI's built-in gesture recognizers don't reliably detect tvOS remote clicks.
struct RemoteTapHandler: UIViewRepresentable {
    let onTap: () -> Void
    let onLongPressLeft: (() -> Void)?
    let onLongPressRight: (() -> Void)?

    init(onTap: @escaping () -> Void, onLongPressLeft: (() -> Void)? = nil, onLongPressRight: (() -> Void)? = nil) {
        self.onTap = onTap
        self.onLongPressLeft = onLongPressLeft
        self.onLongPressRight = onLongPressRight
    }

    func makeUIView(context: Context) -> RemoteTapUIView {
        let view = RemoteTapUIView()
        view.onTap = onTap
        view.onLongPressLeft = onLongPressLeft
        view.onLongPressRight = onLongPressRight
        return view
    }

    func updateUIView(_ uiView: RemoteTapUIView, context: Context) {
        uiView.onTap = onTap
        uiView.onLongPressLeft = onLongPressLeft
        uiView.onLongPressRight = onLongPressRight
    }
}

/// UIView that captures Siri Remote tap via UITapGestureRecognizer.
class RemoteTapUIView: UIView {
    var onTap: (() -> Void)?
    var onLongPressLeft: (() -> Void)?
    var onLongPressRight: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() {
        onTap?()
    }

    override var canBecomeFocused: Bool { true }
}
