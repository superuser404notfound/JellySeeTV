import SwiftUI
import AVKit

/// SwiftUI wrapper around `AVPlayerViewController`.
///
/// `AVPlayerViewController` brings the entire native tvOS player UX
/// for free: scrubbing via the Siri Remote touch surface, transport
/// bar, audio + subtitle picker, info overlay, "skip 10s" with the
/// arrow keys, system pause-on-home, AirPlay, PiP. We don't render
/// any custom controls — just hand the player off to the system.
struct NativeVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        // Don't auto-show now-playing overlay on every event — the
        // system already manages overlay visibility correctly.
        vc.allowsPictureInPicturePlayback = true
        vc.requiresLinearPlayback = false
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Keep the view controller's player in sync if it ever drifts
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
