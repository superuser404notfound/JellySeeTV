import SwiftUI
import AVKit

/// SwiftUI wrapper around AVPlayerViewController for trailer
/// playback. AVKit's view controller is the native tvOS player
/// surface — built-in transport controls, Siri Remote integration,
/// fullscreen by default. We use it specifically for trailers
/// (rather than reusing AetherEngine) because trailers are
/// single-shot streams without the Jellyfin session/progress
/// reporting the main player is built around.
struct DirectVideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.modalPresentationStyle = .fullScreen
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // No live updates — `url` is captured at present time.
    }
}
