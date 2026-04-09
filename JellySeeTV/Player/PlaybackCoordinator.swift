import AVFoundation
import AVKit
import Foundation

@MainActor
final class PlaybackCoordinator {
    let player = AVPlayer()
    private(set) var playMethod: PlayMethod = .directPlay
    private(set) var mediaSourceID: String = ""
    private(set) var playSessionID: String?

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String

    init(playbackService: JellyfinPlaybackServiceProtocol, userID: String) {
        self.playbackService = playbackService
        self.userID = userID
    }

    /// Negotiate playback and start the stream
    func preparePlayback(
        item: JellyfinItem,
        startFromBeginning: Bool
    ) async throws {
        // 1. Get playback info from server
        let info = try await playbackService.getPlaybackInfo(itemID: item.id, userID: userID)
        playSessionID = info.playSessionId

        // 2. Pick best media source
        guard let source = pickBestSource(info.mediaSources) else {
            throw PlaybackError.noCompatibleSource
        }
        mediaSourceID = source.id

        // 3. Determine play method and build URL
        let streamURL: URL?
        let nativeContainers: Set<String> = ["mp4", "m4v", "mov"]
        let isNativeContainer = nativeContainers.contains(source.container?.lowercased() ?? "")

        if source.supportsDirectPlay == true && isNativeContainer {
            // Native container (mp4/mov) -- serve file directly
            playMethod = .directPlay
            streamURL = playbackService.buildStreamURL(
                itemID: item.id, mediaSourceID: source.id, container: source.container, isStatic: true
            )
        } else if source.supportsDirectStream == true {
            // Non-native container (mkv/webm) or DirectPlay not available
            // Jellyfin remuxes to mp4 without re-encoding video/audio
            playMethod = .directStream
            streamURL = playbackService.buildStreamURL(
                itemID: item.id, mediaSourceID: source.id, container: "mp4", isStatic: false
            )
        } else if source.supportsTranscoding == true, let transURL = source.transcodingUrl {
            playMethod = .transcode
            // Server provides relative transcoding URL, resolve against base
            streamURL = playbackService.buildTranscodeURL(relativePath: transURL)
        } else {
            throw PlaybackError.noCompatibleSource
        }

        guard let url = streamURL else {
            throw PlaybackError.invalidStreamURL
        }

        #if DEBUG
        print("[Player] Play method: \(playMethod.rawValue)")
        print("[Player] Stream URL: \(url)")
        print("[Player] DirectPlay: \(source.supportsDirectPlay ?? false), DirectStream: \(source.supportsDirectStream ?? false), Transcode: \(source.supportsTranscoding ?? false)")
        print("[Player] Container: \(source.container ?? "unknown")")
        if let vs = source.mediaStreams?.first(where: { $0.type == .video }) {
            print("[Player] Video: \(vs.codec ?? "?") \(vs.width ?? 0)x\(vs.height ?? 0)")
        }
        #endif

        // 4. Configure AVPlayer
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 30
        player.replaceCurrentItem(with: playerItem)

        // 5. Seek to resume position
        if !startFromBeginning, let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
            let seconds = ticks.ticksToSeconds
            await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000))
        }

        // 6. Set HDR/SDR display mode
        configureDisplayMode(for: source)

        // 7. Start playback
        player.play()
    }

    /// Current playback position in Jellyfin ticks
    var currentPositionTicks: Int64 {
        guard let currentTime = player.currentItem?.currentTime(),
              currentTime.isValid && !currentTime.isIndefinite else { return 0 }
        return Int64(currentTime.seconds * 10_000_000)
    }

    var isPaused: Bool {
        player.timeControlStatus == .paused
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        resetDisplayMode()
    }

    // MARK: - Source Selection

    private func pickBestSource(_ sources: [PlaybackMediaSource]) -> PlaybackMediaSource? {
        // Prefer DirectPlay > DirectStream > Transcode
        if let dp = sources.first(where: { $0.supportsDirectPlay == true }) { return dp }
        if let ds = sources.first(where: { $0.supportsDirectStream == true }) { return ds }
        if let tc = sources.first(where: { $0.supportsTranscoding == true }) { return tc }
        return sources.first
    }

    // MARK: - HDR/SDR

    private func configureDisplayMode(for source: PlaybackMediaSource) {
        // AVPlayer handles HDR/SDR display switching automatically on tvOS
        // when the content has proper HDR metadata. No manual intervention needed.
    }

    private func resetDisplayMode() {
        // No manual reset needed - AVPlayer restores display mode automatically
    }
}

enum PlaybackError: LocalizedError {
    case noCompatibleSource
    case invalidStreamURL

    var errorDescription: String? {
        switch self {
        case .noCompatibleSource:
            "No compatible media source found"
        case .invalidStreamURL:
            "Could not build stream URL"
        }
    }
}
