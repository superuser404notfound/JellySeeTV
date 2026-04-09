import AVFoundation
import AVKit
import Foundation
import TVVLCKit

enum PlayerEngine: Sendable {
    case avPlayer
    case vlcKit
}

@MainActor
final class PlaybackCoordinator: NSObject, VLCMediaPlayerDelegate {
    // Engines
    let avPlayer = AVPlayer()
    let vlcPlayer = VLCMediaPlayer()
    private(set) var engine: PlayerEngine = .avPlayer

    // Playback state
    private(set) var playMethod: PlayMethod = .directPlay
    private(set) var mediaSourceID: String = ""
    private(set) var playSessionID: String?

    // VLCKit callbacks
    var onVLCStateChanged: ((VLCMediaPlayerState) -> Void)?
    var onVLCTimeChanged: ((Int64) -> Void)?
    var onVLCEndReached: (() -> Void)?

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String
    private static let nativeContainers: Set<String> = ["mp4", "m4v", "mov"]

    init(playbackService: JellyfinPlaybackServiceProtocol, userID: String) {
        self.playbackService = playbackService
        self.userID = userID
        super.init()
        vlcPlayer.delegate = self
    }

    // MARK: - Prepare Playback

    func preparePlayback(item: JellyfinItem, startFromBeginning: Bool) async throws {
        // Step 1: Try AVPlayer path first
        let avInfo = try await playbackService.getPlaybackInfo(
            itemID: item.id, userID: userID,
            profile: DirectPlayProfile.avPlayerProfile()
        )
        playSessionID = avInfo.playSessionId

        guard let source = avInfo.mediaSources.first else {
            throw PlaybackError.noCompatibleSource
        }
        mediaSourceID = source.id

        let isNative = Self.nativeContainers.contains(source.container?.lowercased() ?? "")

        if source.supportsDirectPlay == true && isNative {
            // Path 1: AVPlayer DirectPlay (MP4/MOV -- instant)
            engine = .avPlayer
            playMethod = .directPlay
            guard let url = playbackService.buildStreamURL(
                itemID: item.id, mediaSourceID: source.id,
                container: source.container, isStatic: true
            ) else { throw PlaybackError.invalidStreamURL }

            #if DEBUG
            print("[Player] Engine: AVPlayer DirectPlay")
            print("[Player] URL: \(url)")
            #endif

            await startAVPlayer(url: url, item: item, startFromBeginning: startFromBeginning)
            return
        }

        if source.supportsTranscoding == true, let transURL = source.transcodingUrl {
            // Path 2: AVPlayer HLS Remux (MKV → HLS, only container change, 2-3s)
            engine = .avPlayer
            playMethod = .directStream
            guard let url = playbackService.buildTranscodeURL(relativePath: transURL) else {
                throw PlaybackError.invalidStreamURL
            }

            #if DEBUG
            print("[Player] Engine: AVPlayer HLS Remux")
            print("[Player] URL: \(url)")
            #endif

            await startAVPlayer(url: url, item: item, startFromBeginning: startFromBeginning)
            return
        }

        // Step 2: VLCKit fallback for exotic codecs
        let vlcInfo = try await playbackService.getPlaybackInfo(
            itemID: item.id, userID: userID,
            profile: DirectPlayProfile.vlcKitProfile()
        )
        guard let vlcSource = vlcInfo.mediaSources.first else {
            throw PlaybackError.noCompatibleSource
        }
        mediaSourceID = vlcSource.id
        playSessionID = vlcInfo.playSessionId

        engine = .vlcKit
        playMethod = .directPlay
        guard let url = playbackService.buildStreamURL(
            itemID: item.id, mediaSourceID: vlcSource.id,
            container: vlcSource.container, isStatic: true
        ) else { throw PlaybackError.invalidStreamURL }

        #if DEBUG
        print("[Player] Engine: VLCKit DirectPlay")
        print("[Player] URL: \(url)")
        #endif

        let media = VLCMedia(url: url)
        media.addOptions(["network-caching": 1500])
        vlcPlayer.media = media
        vlcPlayer.play()
        if !startFromBeginning, let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
            try? await Task.sleep(for: .milliseconds(500))
            vlcPlayer.time = VLCTime(int: Int32(ticks / 10_000))
        }
    }

    // MARK: - AVPlayer Setup

    private func startAVPlayer(url: URL, item: JellyfinItem, startFromBeginning: Bool) async {
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 5
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        avPlayer.replaceCurrentItem(with: playerItem)

        // Wait until player has enough data to start without audio-before-video
        await waitForReadyToPlay(playerItem)

        if !startFromBeginning, let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
            await avPlayer.seek(to: CMTime(seconds: ticks.ticksToSeconds, preferredTimescale: 1000))
        }

        avPlayer.play()
    }

    private func waitForReadyToPlay(_ item: AVPlayerItem) async {
        // Wait up to 10 seconds for the item to be ready
        for _ in 0..<100 {
            if item.status == .readyToPlay { return }
            if item.status == .failed { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Controls

    func togglePlayPause() {
        switch engine {
        case .avPlayer:
            if avPlayer.timeControlStatus == .playing {
                avPlayer.pause()
            } else {
                avPlayer.play()
            }
        case .vlcKit:
            if vlcPlayer.isPlaying { vlcPlayer.pause() } else { vlcPlayer.play() }
        }
    }

    func seekForward(_ seconds: Int32 = 10) {
        switch engine {
        case .avPlayer:
            let current = avPlayer.currentTime()
            avPlayer.seek(to: CMTimeAdd(current, CMTime(seconds: Double(seconds), preferredTimescale: 1)))
        case .vlcKit:
            vlcPlayer.jumpForward(seconds)
        }
    }

    func seekBackward(_ seconds: Int32 = 10) {
        switch engine {
        case .avPlayer:
            let current = avPlayer.currentTime()
            avPlayer.seek(to: CMTimeSubtract(current, CMTime(seconds: Double(seconds), preferredTimescale: 1)))
        case .vlcKit:
            vlcPlayer.jumpBackward(seconds)
        }
    }

    func stop() {
        switch engine {
        case .avPlayer:
            avPlayer.pause()
            avPlayer.replaceCurrentItem(with: nil)
        case .vlcKit:
            vlcPlayer.stop()
        }
    }

    // MARK: - Position

    var currentPositionTicks: Int64 {
        switch engine {
        case .avPlayer:
            let time = avPlayer.currentTime()
            guard time.isValid && !time.isIndefinite else { return 0 }
            return Int64(time.seconds * 10_000_000)
        case .vlcKit:
            return Int64(vlcPlayer.time.intValue) * 10_000
        }
    }

    var isPlaying: Bool {
        switch engine {
        case .avPlayer: avPlayer.timeControlStatus == .playing
        case .vlcKit: vlcPlayer.isPlaying
        }
    }

    var isPaused: Bool {
        switch engine {
        case .avPlayer: avPlayer.timeControlStatus == .paused
        case .vlcKit: vlcPlayer.state == .paused
        }
    }

    // MARK: - VLCKit Audio/Subtitle Tracks

    var vlcAudioTracks: [(index: Int, name: String)] {
        guard engine == .vlcKit,
              let names = vlcPlayer.audioTrackNames as? [String],
              let indexes = vlcPlayer.audioTrackIndexes as? [NSNumber] else { return [] }
        return zip(indexes, names).map { (Int(truncating: $0.0), $0.1) }
    }

    var vlcSubtitleTracks: [(index: Int, name: String)] {
        guard engine == .vlcKit,
              let names = vlcPlayer.videoSubTitlesNames as? [String],
              let indexes = vlcPlayer.videoSubTitlesIndexes as? [NSNumber] else { return [] }
        return zip(indexes, names).map { (Int(truncating: $0.0), $0.1) }
    }

    // MARK: - VLCMediaPlayerDelegate

    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        Task { @MainActor in
            onVLCStateChanged?(vlcPlayer.state)
            if vlcPlayer.state == .ended || vlcPlayer.state == .stopped {
                onVLCEndReached?()
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor in
            onVLCTimeChanged?(currentPositionTicks)
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
