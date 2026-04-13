import Foundation
import Combine
import Observation
import SteelPlayer

/// ViewModel that bridges SteelPlayer with Jellyfin session reporting
/// and our custom tvOS-style player UI.
///
/// Uses Combine subscriptions to observe SteelPlayer's @Published
/// properties instead of polling timers — eliminates AttributeGraph cycles.
@Observable
@MainActor
final class PlayerViewModel {

    // MARK: - UI State

    var isLoading = true
    var errorMessage: String?
    var isPlaying = false
    var showControls = false

    // Time display
    var currentTime: String = "00:00"
    var totalTime: String = "00:00"
    var remainingTime: String = "-00:00"
    var progress: Float = 0

    // Playback time (raw seconds, tracked by @Observable for subtitle sync)
    var playbackTime: Double = 0

    // Scrubbing
    var isScrubbing = false
    var scrubProgress: Float = 0
    var scrubTime: String = "00:00"
    var displayedProgress: Float { isScrubbing ? scrubProgress : progress }
    private var scrubStartProgress: Float = 0

    // Custom focus for transport bar navigation
    var controlsFocus: ControlsFocus = .progressBar
    var trackDropdown: TrackDropdown = .none

    enum ControlsFocus: Hashable {
        case progressBar
        case audioButton
        case subtitleButton
    }

    enum TrackDropdown: Equatable {
        case none
        case audio(highlighted: Int)   // index into player.audioTracks
        case subtitle(highlighted: Int) // index into subtitle items (0=Off, 1..=tracks)
    }

    var isDropdownOpen: Bool { trackDropdown != .none }

    // Tracks
    var subtitleCues: [SubtitleCue] = []
    var activeAudioIndex: Int?
    var activeSubtitleIndex: Int?

    // MARK: - Dependencies

    let item: JellyfinItem
    let player = try! SteelPlayer()

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String
    private let startFromBeginning: Bool
    private var cachedPlaybackInfo: PlaybackInfoResponse?

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: Task<Void, Never>?
    var controlsTimer: Task<Void, Never>?
    private var hasReportedStart = false
    private var hasStartedPlaying = false
    private var mediaSourceID: String = ""
    private var playSessionID: String?
    private var activePlayMethod: PlayMethod = .directPlay
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

            subtitleStreams = source.mediaStreams?.filter { $0.type == .subtitle } ?? []

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

            let startPos: Double? = if !startFromBeginning,
                let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
                ticks.ticksToSeconds
            } else {
                nil
            }

            try await player.load(url: url, startPosition: startPos)

            totalTime = formatSeconds(effectiveDuration)
            activeAudioIndex = player.audioTracks.first(where: { $0.isDefault })?.id
                ?? player.audioTracks.first?.id
            isLoading = false
            isPlaying = true

            startObserving()
            await reportStart()
            startProgressReporting()

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func stopPlayback() async {
        stopProgressReporting()
        cancellables.removeAll()
        await reportStop()
        player.stop()
    }

    // MARK: - State Observation (Combine)

    private func startObserving() {
        player.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .playing:
                    self.hasStartedPlaying = true
                    self.isLoading = false
                    self.isPlaying = true
                case .paused:
                    self.isLoading = false
                    self.isPlaying = false
                case .idle:
                    self.isPlaying = false
                case .loading:
                    if !self.hasStartedPlaying { self.isLoading = true }
                case .seeking:
                    break
                case .error(let msg):
                    self.errorMessage = msg
                    self.isLoading = false
                }
            }
            .store(in: &cancellables)

        player.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self else { return }
                self.playbackTime = time
                guard !self.isScrubbing else { return }
                let dur = self.effectiveDuration
                self.currentTime = self.formatSeconds(time)
                let remaining = dur - time
                self.remainingTime = remaining > 0 ? "-\(self.formatSeconds(remaining))" : "-00:00"
                self.progress = dur > 0 ? Float(time / dur) : 0
            }
            .store(in: &cancellables)

        player.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                guard let self else { return }
                self.totalTime = dur > 0 ? self.formatSeconds(dur) : "00:00"
            }
            .store(in: &cancellables)
    }

    // MARK: - Controls

    func togglePlayPause() {
        player.togglePlayPause()
        showControls = true
        scheduleControlsHide()
    }

    func seekJump(seconds: Double) {
        let dur = effectiveDuration
        guard dur > 0 else { return }

        if !isScrubbing {
            isScrubbing = true
            scrubStartProgress = progress
            scrubProgress = progress
        }

        showControls = true
        controlsTimer?.cancel()

        let jumpProgress = Float(seconds / dur)
        scrubProgress = max(0, min(1, scrubProgress + jumpProgress))
        scrubTime = formatSeconds(Double(scrubProgress) * dur)
    }

    func selectAudioTrack(id: Int) {
        activeAudioIndex = id
        player.selectAudioTrack(index: id)
    }

    func selectSubtitleTrack(id: Int?) {
        if let id {
            activeSubtitleIndex = id
            #if DEBUG
            print("[Subtitles] Selected track index \(id)")
            #endif
            Task { await loadSubtitles(streamIndex: id) }
        } else {
            activeSubtitleIndex = nil
            subtitleCues = []
            #if DEBUG
            print("[Subtitles] Disabled")
            #endif
        }
    }

    private func loadSubtitles(streamIndex: Int) async {
        // Always request SRT — Jellyfin converts ASS/PGS/VTT server-side.
        let format = "srt"
        #if DEBUG
        if let stream = subtitleStreams.first(where: { $0.index == streamIndex }) {
            print("[Subtitles] Stream \(streamIndex): source codec=\(stream.codec ?? "nil"), requesting as srt")
        }
        #endif

        guard let url = playbackService.buildSubtitleURL(
            itemID: item.id,
            mediaSourceID: mediaSourceID,
            streamIndex: streamIndex,
            format: format
        ) else {
            #if DEBUG
            print("[Subtitles] Failed to build URL")
            #endif
            return
        }
        #if DEBUG
        print("[Subtitles] Fetching: \(url.absoluteString.prefix(120))...")
        #endif

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

    func scrub(delta: CGFloat) {
        let dur = effectiveDuration
        guard dur > 0 else { return }

        if !isScrubbing {
            isScrubbing = true
            scrubStartProgress = progress
            showControls = true
            controlsTimer?.cancel()
        }

        scrubProgress = max(0, min(1, scrubStartProgress + Float(delta) * 0.3))
        scrubTime = formatSeconds(Double(scrubProgress) * dur)
    }

    func scrubPanEnded() {
        if isScrubbing {
            scrubStartProgress = scrubProgress
        }
    }

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

    func cancelScrub() {
        isScrubbing = false
        scheduleControlsHide()
    }

    func showControlsTemporarily() {
        showControls = true
        scheduleControlsHide()
    }

    func hideControls() {
        showControls = false
        controlsFocus = .progressBar
        trackDropdown = .none
    }

    func scheduleControlsHide() {
        controlsTimer?.cancel()
        guard isPlaying else { return }
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            hideControls()
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
