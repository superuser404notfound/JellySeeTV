import SwiftUI
import UIKit
import VLCKitSPM

/// UIViewRepresentable that hosts the UIView VLC renders into.
///
/// This view *owns* the VLCMediaPlayer (like Swiftfin/VLCUI's
/// UIVLCVideoPlayerView). Creating the player and its drawable subview
/// in the same synchronous init avoids a race condition in libvlc's
/// internal video-output thread setup that wedges playback in an
/// infinite buffering loop on tvOS.
///
/// The engine is a thin state container; it gets a weak reference to
/// the player via `engine.bind(player:)` once the view exists.
struct VideoLayerView: UIViewRepresentable {
    let engine: VLCPlayerEngine

    func makeUIView(context: Context) -> VLCContainerView {
        VLCContainerView(engine: engine)
    }

    func updateUIView(_ uiView: VLCContainerView, context: Context) {
        // Auto Layout handles resizes; nothing to do here.
    }
}

/// UIView that owns the VLCMediaPlayer and a constraint-pinned drawable
/// subview. Implements VLCMediaPlayerDelegate and forwards events to the
/// engine on the main actor.
final class VLCContainerView: UIView, VLCMediaPlayerDelegate {
    private weak var engine: VLCPlayerEngine?
    private let player: VLCMediaPlayer
    private let contentView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    init(engine: VLCPlayerEngine) {
        self.engine = engine
        // Player and drawable are created together, in this synchronous
        // init, before any layout pass. This is the supported tvOS pattern.
        self.player = VLCMediaPlayer()
        super.init(frame: .zero)

        backgroundColor = .black
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        player.delegate = self
        player.drawable = contentView

        // Hand the player back to the engine so it can drive load/play/seek.
        // bind() is also responsible for replaying any pending load() that
        // happened before the view was attached.
        engine.bind(player: player)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func removeFromSuperview() {
        // Stop playback before the view leaves the hierarchy. We can't do
        // this in deinit under Swift 6 strict concurrency since
        // VLCMediaPlayer isn't Sendable.
        player.stop()
        super.removeFromSuperview()
    }

    override var canBecomeFocused: Bool { false }

    // MARK: - VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.engine?.handleStateChanged(state: self.player.state)
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.engine?.handleTimeChanged(
                timeMs: self.player.time.intValue,
                lengthMs: self.player.media?.length.intValue ?? 0
            )
        }
    }
}
