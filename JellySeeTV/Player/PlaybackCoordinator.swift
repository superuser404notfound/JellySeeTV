import AVFoundation
import AVKit
import Combine
import Foundation
import TVVLCKit

enum PlayerEngine: Sendable {
    case avPlayer
    case vlcKit
}

@MainActor
final class PlaybackCoordinator: NSObject, VLCMediaPlayerDelegate {
    let avPlayer = AVPlayer()
    let vlcPlayer = VLCMediaPlayer()
    private(set) var engine: PlayerEngine = .avPlayer
    private(set) var playMethod: PlayMethod = .directPlay
    private(set) var mediaSourceID: String = ""
    private(set) var playSessionID: String?

    var onVLCStateChanged: ((VLCMediaPlayerState) -> Void)?
    var onVLCTimeChanged: ((Int64) -> Void)?
    var onVLCEndReached: (() -> Void)?

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String
    private var cancellables = Set<AnyCancellable>()
    private static let nativeContainers: Set<String> = ["mp4", "m4v", "mov"]

    init(playbackService: JellyfinPlaybackServiceProtocol, userID: String) {
        self.playbackService = playbackService
        self.userID = userID
        super.init()
        vlcPlayer.delegate = self
    }

    // MARK: - Prepare Playback

    func preparePlayback(item: JellyfinItem, startFromBeginning: Bool, cachedPlaybackInfo: PlaybackInfoResponse? = nil) async throws {
        let avInfo: PlaybackInfoResponse
        if let cached = cachedPlaybackInfo {
            avInfo = cached
        } else {
            avInfo = try await playbackService.getPlaybackInfo(
                itemID: item.id, userID: userID,
                profile: DirectPlayProfile.avPlayerProfile()
            )
        }
        playSessionID = avInfo.playSessionId

        guard let source = avInfo.mediaSources.first else {
            throw PlaybackError.noCompatibleSource
        }
        mediaSourceID = source.id

        let isNative = Self.nativeContainers.contains(source.container?.lowercased() ?? "")

        if source.supportsDirectPlay == true && isNative {
            engine = .avPlayer
            playMethod = .directPlay
            guard let url = playbackService.buildStreamURL(
                itemID: item.id, mediaSourceID: source.id,
                container: source.container, isStatic: true
            ) else { throw PlaybackError.invalidStreamURL }

            try await startAVPlayer(url: url, item: item, startFromBeginning: startFromBeginning)
            return
        }

        if source.supportsTranscoding == true, let transURL = source.transcodingUrl {
            engine = .avPlayer
            playMethod = .directStream
            guard let url = playbackService.buildTranscodeURL(relativePath: transURL) else {
                throw PlaybackError.invalidStreamURL
            }

            try await startAVPlayer(url: url, item: item, startFromBeginning: startFromBeginning)
            return
        }

        // VLCKit fallback -- reuse same source info, no extra API call
        engine = .vlcKit
        playMethod = .directPlay
        guard let url = playbackService.buildStreamURL(
            itemID: item.id, mediaSourceID: source.id,
            container: source.container, isStatic: true
        ) else { throw PlaybackError.invalidStreamURL }

        let media = VLCMedia(url: url)
        media.addOptions(["network-caching": 1500])
        vlcPlayer.media = media
        vlcPlayer.play()
        if !startFromBeginning, let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
            try? await Task.sleep(for: .milliseconds(800))
            vlcPlayer.time = VLCTime(int: Int32(ticks / 10_000))
        }
    }

    // MARK: - AVPlayer Setup

    private func startAVPlayer(url: URL, item: JellyfinItem, startFromBeginning: Bool) async throws {
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 10

        // Don't auto-play -- we control when playback starts
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        avPlayer.replaceCurrentItem(with: playerItem)

        // Wait for the player item to actually be ready (proper KVO, not polling)
        try await waitForPlayerReady(playerItem)

        // Seek BEFORE play, using completion handler
        if !startFromBeginning, let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
            await seekAVPlayer(to: ticks.ticksToSeconds)
        }

        // Start playback -- playImmediately ensures audio+video sync
        avPlayer.playImmediately(atRate: 1.0)
    }

    private func waitForPlayerReady(_ item: AVPlayerItem) async throws {
        // Use Combine to properly observe status changes instead of polling
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false

            item.publisher(for: \.status)
                .filter { $0 != .unknown }
                .first()
                .sink { status in
                    guard !resumed else { return }
                    resumed = true
                    if status == .readyToPlay {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: PlaybackError.invalidStreamURL)
                    }
                }
                .store(in: &cancellables)

            // Timeout after 15 seconds
            Task {
                try? await Task.sleep(for: .seconds(15))
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: PlaybackError.invalidStreamURL)
            }
        }
    }

    private func seekAVPlayer(to seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            let time = CMTime(seconds: seconds, preferredTimescale: 10000)
            avPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Controls

    func togglePlayPause() {
        switch engine {
        case .avPlayer:
            if avPlayer.timeControlStatus == .playing { avPlayer.pause() } else { avPlayer.play() }
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
        cancellables.removeAll()
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

    // MARK: - VLCKit Tracks

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
