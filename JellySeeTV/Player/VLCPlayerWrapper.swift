import SwiftUI
import TVVLCKit

/// UIViewRepresentable that hosts the VLCMediaPlayer video output.
struct VLCPlayerWrapper: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if player.drawable as? UIView !== uiView {
            player.drawable = uiView
        }
    }
}
