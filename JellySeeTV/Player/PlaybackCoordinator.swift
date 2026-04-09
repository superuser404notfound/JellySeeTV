import Foundation
import TVVLCKit

@MainActor
final class PlaybackCoordinator: NSObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    private(set) var playMethod: PlayMethod = .directPlay
    private(set) var mediaSourceID: String = ""
    private(set) var playSessionID: String?
    private(set) var duration: Int64 = 0 // ticks

    // Callbacks for state changes
    var onStateChanged: ((VLCMediaPlayerState) -> Void)?
    var onTimeChanged: ((Int64) -> Void)?  // position in ticks
    var onEndReached: (() -> Void)?

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String

    init(playbackService: JellyfinPlaybackServiceProtocol, userID: String) {
        self.playbackService = playbackService
        self.userID = userID
        super.init()
        player.delegate = self
    }

    // MARK: - Prepare and Start

    func preparePlayback(item: JellyfinItem, startFromBeginning: Bool) async throws {
        // 1. Get playback info
        let info = try await playbackService.getPlaybackInfo(itemID: item.id, userID: userID)
        playSessionID = info.playSessionId

        // 2. Pick best source -- with VLCKit we can always DirectPlay
        guard let source = info.mediaSources.first else {
            throw PlaybackError.noCompatibleSource
        }
        mediaSourceID = source.id

        // 3. Build DirectPlay URL (always Static=true, VLCKit handles everything)
        playMethod = .directPlay
        guard let streamURL = playbackService.buildStreamURL(
            itemID: item.id,
            mediaSourceID: source.id,
            container: source.container,
            isStatic: true
        ) else {
            throw PlaybackError.invalidStreamURL
        }

        #if DEBUG
        print("[VLC Player] DirectPlay URL: \(streamURL)")
        print("[VLC Player] Container: \(source.container ?? "?")")
        if let vs = source.mediaStreams?.first(where: { $0.type == .video }) {
            print("[VLC Player] Video: \(vs.codec ?? "?") \(vs.width ?? 0)x\(vs.height ?? 0)")
        }
        #endif

        // 4. Configure VLCMediaPlayer
        let media = VLCMedia(url: streamURL)
        media.addOptions([
            "network-caching": 1000,
            "clock-jitter": 0,
            "file-caching": 1000,
            "live-caching": 1000,
        ])
        player.media = media

        // 5. Start playback
        player.play()

        // 6. Seek to resume position
        if !startFromBeginning, let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
            let ms = Int32(ticks / 10_000) // ticks to milliseconds
            // Wait briefly for player to initialize before seeking
            try? await Task.sleep(for: .milliseconds(500))
            player.time = VLCTime(int: ms)
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func seekForward(_ seconds: Int32 = 10) {
        player.jumpForward(seconds)
    }

    func seekBackward(_ seconds: Int32 = 10) {
        player.jumpBackward(seconds)
    }

    func seekTo(fraction: Float) {
        player.position = fraction
    }

    func stop() {
        player.stop()
    }

    // MARK: - Position / Duration

    var currentPositionTicks: Int64 {
        let ms = player.time.intValue
        return Int64(ms) * 10_000 // ms to ticks
    }

    var durationTicks: Int64 {
        let ms = player.media?.length.intValue ?? 0
        return Int64(ms) * 10_000
    }

    var position: Float {
        player.position
    }

    var isPlaying: Bool {
        player.isPlaying
    }

    var isPaused: Bool {
        player.state == .paused
    }

    // MARK: - Audio Tracks

    var audioTracks: [(index: Int, name: String)] {
        guard let names = player.audioTrackNames as? [String],
              let indexes = player.audioTrackIndexes as? [NSNumber] else { return [] }
        return zip(indexes, names).map { (Int(truncating: $0.0), $0.1) }
    }

    var currentAudioTrack: Int {
        get { Int(player.currentAudioTrackIndex) }
        set { player.currentAudioTrackIndex = Int32(newValue) }
    }

    // MARK: - Subtitle Tracks

    var subtitleTracks: [(index: Int, name: String)] {
        guard let names = player.videoSubTitlesNames as? [String],
              let indexes = player.videoSubTitlesIndexes as? [NSNumber] else { return [] }
        return zip(indexes, names).map { (Int(truncating: $0.0), $0.1) }
    }

    var currentSubtitleTrack: Int {
        get { Int(player.currentVideoSubTitleIndex) }
        set { player.currentVideoSubTitleIndex = Int32(newValue) }
    }

    // MARK: - VLCMediaPlayerDelegate

    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        Task { @MainActor in
            let state = player.state
            onStateChanged?(state)

            if state == .ended || state == .stopped {
                onEndReached?()
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor in
            onTimeChanged?(currentPositionTicks)
        }
    }
}

enum PlaybackError: LocalizedError {
    case noCompatibleSource
    case invalidStreamURL

    var errorDescription: String? {
        switch self {
        case .noCompatibleSource: "No compatible media source found"
        case .invalidStreamURL: "Could not build stream URL"
        }
    }
}
