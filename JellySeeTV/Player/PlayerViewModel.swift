import Foundation
import Observation
import SteelPlayer

/// ViewModel that bridges SteelPlayer with Jellyfin session reporting
/// and our custom tvOS-style player UI.
@Observable
@MainActor
final class PlayerViewModel {
    var isLoading = true
    var errorMessage: String?
    var isPlaying = false
    var showControls = false
    var currentTime: String = "00:00"
    var totalTime: String = "00:00"
    var remainingTime: String = "-00:00"
    var progress: Float = 0

    // Scrubbing state
    var isScrubbing = false
    var scrubProgress: Float = 0
    var scrubTime: String = "00:00"
    var displayedProgress: Float { isScrubbing ? scrubProgress : progress }
    private var scrubStartProgress: Float = 0

    let item: JellyfinItem
    let player = try! SteelPlayer()  // Metal is guaranteed on Apple TV

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String
    private let startFromBeginning: Bool
    private var cachedPlaybackInfo: PlaybackInfoResponse?
    private var progressTimer: Task<Void, Never>?
    private var controlsTimer: Task<Void, Never>?
    private var stateObserver: Task<Void, Never>?
    private var hasReportedStart = false
    private var hasStartedPlaying = false
    private var mediaSourceID: String = ""
    private var playSessionID: String?
    private var activePlayMethod: PlayMethod = .directPlay

    // Subtitle state
    var subtitleCues: [SubtitleCue] = []
    var activeSubtitleIndex: Int?
    private var subtitleStreams: [MediaStream] = []

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, cachedPlaybackInfo: PlaybackInfoResponse? = nil) {
        self.item = item
        self.startFromBeginning = startFromBeginning
        self.playbackService = playbackService
        self.userID = userID
        self.cachedPlaybackInfo = cachedPlaybackInfo
    }

    // MARK: - Lifecycle

    func startPlayback() async {
        isLoading = true
        errorMessage = nil

        do {
            // Use cached info only if it has valid media sources.
            // Stale/wrong caches (e.g. from a Series instead of Episode)
            // will have empty mediaSources — fall through to a fresh request.
            let info: PlaybackInfoResponse
            if let cached = cachedPlaybackInfo, !cached.mediaSources.isEmpty {
                info = cached
            } else {
                info = try await playbackService.getPlaybackInfo(
                    itemID: item.id,
                    userID: userID,
                    profile: DirectPlayProfile.current()
                )
            }
            playSessionID = info.playSessionId

            guard let source = info.mediaSources.first else {
                throw PlayerEngineError.noSource
            }
            mediaSourceID = source.id

            #if DEBUG
            print("[PlayerViewModel] Source: container=\(source.container ?? "nil"), directPlay=\(source.supportsDirectPlay ?? false), directStream=\(source.supportsDirectStream ?? false), transcoding=\(source.supportsTranscoding ?? false)")
            if let tURL = source.transcodingUrl {
                print("[PlayerViewModel] TranscodingURL: \(tURL.prefix(120))...")
            }
            #endif

            // Build URL — prefer direct play/stream (single file) over transcoding.
            // SteelPlayer's AVIO context handles HTTP progressive downloads but
            // Store subtitle streams for later loading
            subtitleStreams = source.mediaStreams?.filter { $0.type == .subtitle } ?? []

            // cannot handle HLS playlists.
            let url: URL
            if source.supportsDirectPlay == true || source.supportsDirectStream == true {
                let isDirectPlay = source.supportsDirectPlay == true
                guard let directURL = playbackService.buildStreamURL(
                    itemID: item.id,
                    mediaSourceID: source.id,
                    container: source.container,
                    isStatic: isDirectPlay
                ) else {
                    throw PlayerEngineError.noURL
                }
                url = directURL
                activePlayMethod = isDirectPlay ? .directPlay : .directStream
                #if DEBUG
                print("[PlayerViewModel] Using direct \(isDirectPlay ? "play" : "stream")")
                #endif
            } else if let transcodePath = source.transcodingUrl, !transcodePath.isEmpty {
                guard let transcodeURL = playbackService.buildTranscodeURL(relativePath: transcodePath) else {
                    throw PlayerEngineError.noURL
                }
                url = transcodeURL
                activePlayMethod = .transcode
                #if DEBUG
                print("[PlayerViewModel] Using transcoded stream")
                #endif
            } else {
                throw PlayerEngineError.noURL
            }

            // Start position
            let startPos: Double? = if !startFromBeginning,
                let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
                ticks.ticksToSeconds
            } else {
                nil
            }

            // Load with SteelPlayer — this opens the demuxer, starts
            // the decoder, and begins the render loop.
            try await player.load(url: url, startPosition: startPos)

            totalTime = formatSeconds(effectiveDuration)
            isLoading = false
            isPlaying = true

            startStateObserver()
            await reportStart()
            startProgressReporting()

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func stopPlayback() async {
        stopProgressReporting()
        stateObserver?.cancel()
        await reportStop()
        player.stop()
    }

    // MARK: - Controls

    func togglePlayPause() {
        player.togglePlayPause()
        showControls = true
        scheduleControlsHide()
    }

    /// Jump forward/backward with preview — doesn't seek until confirmed.
    /// Multiple jumps accumulate (e.g. 3x right = +30s preview).
    func seekJump(seconds: Double) {
        let dur = effectiveDuration
        guard dur > 0 else { return }

        if !isScrubbing {
            // Start a pending seek from current position
            isScrubbing = true
            scrubStartProgress = progress
            scrubProgress = progress
        }

        // Accumulate jump
        let jumpProgress = Float(seconds / dur)
        let newProgress = max(0, min(1, scrubProgress + jumpProgress))
        scrubProgress = newProgress
        scrubTime = formatSeconds(Double(newProgress) * dur)
    }

    func selectAudioTrack(id: Int) {
        player.selectAudioTrack(index: id)
    }

    func selectSubtitleTrack(id: Int?) {
        if let id {
            activeSubtitleIndex = id
            Task { await loadSubtitles(streamIndex: id) }
        } else {
            activeSubtitleIndex = nil
            subtitleCues = []
        }
    }

    private func loadSubtitles(streamIndex: Int) async {
        // Find the subtitle stream info to determine format
        let format: String
        if let stream = subtitleStreams.first(where: { $0.index == streamIndex }) {
            format = stream.codec ?? "srt"
        } else {
            format = "srt"
        }

        guard let url = playbackService.buildSubtitleURL(
            itemID: item.id,
            mediaSourceID: mediaSourceID,
            streamIndex: streamIndex,
            format: format
        ) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else { return }
            subtitleCues = SRTParser.parse(content)
            #if DEBUG
            print("[Subtitles] Loaded \(subtitleCues.count) cues for stream \(streamIndex)")
            #endif
        } catch {
            #if DEBUG
            print("[Subtitles] Failed to load: \(error)")
            #endif
        }
    }

    // MARK: - Scrubbing

    var effectiveDuration: Double {
        if player.duration > 0 { return player.duration }
        if let ticks = item.runTimeTicks, ticks > 0 {
            return Double(ticks) / 10_000_000
        }
        return 0
    }

    /// Start or update scrubbing with a normalized pan delta (-1.0 to 1.0).
    func scrub(delta: CGFloat) {
        let dur = effectiveDuration
        guard dur > 0 else { return }

        if !isScrubbing {
            isScrubbing = true
            scrubStartProgress = progress
            showControls = true
            controlsTimer?.cancel()
        }

        // Map pan delta to progress (full swipe = 30% of duration)
        let newProgress = max(0, min(1, scrubStartProgress + Float(delta) * 0.3))
        scrubProgress = newProgress
        scrubTime = formatSeconds(Double(newProgress) * dur)
    }

    /// Called when pan gesture ends — update start position so the next
    /// swipe continues from where the user left off, not from the beginning.
    func scrubPanEnded() {
        if isScrubbing {
            scrubStartProgress = scrubProgress
        }
    }

    /// Commit the scrub — seek to the scrubbed position.
    func commitScrub() {
        let dur = effectiveDuration
        guard isScrubbing, dur > 0 else {
            isScrubbing = false
            return
        }
        let targetTime = Double(scrubProgress) * dur
        isScrubbing = false
        Task {
            await player.seek(to: targetTime)
            scheduleControlsHide()
        }
    }

    /// Cancel scrubbing without seeking.
    func cancelScrub() {
        isScrubbing = false
        scheduleControlsHide()
    }

    func showControlsTemporarily() {
        showControls = true
        scheduleControlsHide()
    }

    func handleClick() {
        if !showControls {
            showControls = true
            scheduleControlsHide()
            return
        }
        player.togglePlayPause()
        showControls = true
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsTimer?.cancel()
        guard isPlaying else { return }
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - State Observer

    private func startStateObserver() {
        stateObserver = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }

                if !isScrubbing {
                    let dur = effectiveDuration
                    let cur = player.currentTime
                    currentTime = formatSeconds(cur)
                    let remaining = dur - cur
                    remainingTime = remaining > 0 ? "-\(formatSeconds(remaining))" : "-00:00"
                    progress = dur > 0 ? Float(cur / dur) : 0
                    let formattedDur = dur > 0 ? formatSeconds(dur) : "00:00"
                    if totalTime != formattedDur {
                        totalTime = formattedDur
                    }
                }

                switch player.state {
                case .playing:
                    hasStartedPlaying = true
                    isLoading = false
                    isPlaying = true
                case .paused:
                    isLoading = false
                    isPlaying = false
                case .idle:
                    isPlaying = false
                case .loading:
                    if !hasStartedPlaying {
                        isLoading = true
                    }
                case .seeking:
                    break
                case .error(let msg):
                    errorMessage = msg
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Jellyfin Session Reporting

    private var currentPositionTicks: Int64 {
        Int64(player.currentTime * 10_000_000)
    }

    private func reportStart() async {
        guard !hasReportedStart else { return }
        hasReportedStart = true
        let report = PlaybackStartReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks,
            canSeek: true,
            playMethod: activePlayMethod.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackStart(report)
    }

    private func reportProgress() async {
        let report = PlaybackProgressReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks,
            isPaused: player.state == .paused,
            canSeek: true,
            playMethod: activePlayMethod.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackProgress(report)
    }

    private func reportStop() async {
        let report = PlaybackStopReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks
        )
        try? await playbackService.reportPlaybackStopped(report)
    }

    private func startProgressReporting() {
        progressTimer?.cancel()
        progressTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await reportProgress()
            }
        }
    }

    private func stopProgressReporting() {
        progressTimer?.cancel()
        progressTimer = nil
    }
}

private enum PlayerEngineError: LocalizedError {
    case noSource
    case noURL

    var errorDescription: String? {
        switch self {
        case .noSource: "No media source available"
        case .noURL: "Could not build stream URL"
        }
    }
}
