import Foundation
import Combine
import Observation
import AetherEngine
import AVKit

/// ViewModel that bridges AetherEngine with Jellyfin session reporting
/// and our custom tvOS-style player UI.
///
/// Uses Combine subscriptions to observe AetherEngine's @Published
/// properties instead of polling timers — eliminates AttributeGraph cycles.
///
/// Split into extensions:
/// - `PlayerViewModel+Scrubbing.swift` — pan/arrow scrubbing
/// - `PlayerViewModel+NextEpisode.swift` — auto-play next episode
/// - `PlayerViewModel+SessionReporting.swift` — Jellyfin progress reports
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
    var scrubStartProgress: Float = 0

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

    // Video format (HDR/DV indicator)
    var videoFormat: VideoFormat = .sdr

    // Next episode
    var nextEpisode: JellyfinItem?
    var showNextEpisodeOverlay = false
    var nextEpisodeCountdown = 10
    var nextEpisodeTimer: Task<Void, Never>?
    var hasFetchedNextEpisode = false
    var nextEpisodeCancelled = false

    // MARK: - Dependencies

    var item: JellyfinItem
    let player: AetherEngine

    let playbackService: JellyfinPlaybackServiceProtocol
    let userID: String
    var startFromBeginning: Bool
    var cachedPlaybackInfo: PlaybackInfoResponse?

    // MARK: - Internal State

    var cancellables = Set<AnyCancellable>()
    var progressTimer: Task<Void, Never>?
    var controlsTimer: Task<Void, Never>?
    var hasReportedStart = false
    var hasStartedPlaying = false
    /// The position we resumed from — used as minimum for progress reports
    /// to prevent Jellyfin from resetting progress when stopping early.
    var resumePositionTicks: Int64 = 0
    var mediaSourceID: String = ""
    var playSessionID: String?
    var activePlayMethod: PlayMethod = .directPlay
    var subtitleStreams: [MediaStream] = []

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, cachedPlaybackInfo: PlaybackInfoResponse? = nil) throws {
        self.item = item
        self.player = try AetherEngine()
        self.startFromBeginning = startFromBeginning
        self.playbackService = playbackService
        self.userID = userID
        self.cachedPlaybackInfo = cachedPlaybackInfo
    }

    // MARK: - Lifecycle

    func startPlayback() async {
        isLoading = true
        errorMessage = nil
        #if DEBUG
        print("[PlayerVM] startPlayback: item=\(item.name), seriesId=\(item.seriesId ?? "nil"), type=\(item.type)")
        #endif

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

            let startPos: Double?
            if !startFromBeginning,
               let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
                startPos = ticks.ticksToSeconds
                resumePositionTicks = ticks
            } else {
                startPos = nil
                resumePositionTicks = 0
            }

            // Set display criteria BEFORE loading — the TV needs time to switch
            // to HDR/DV mode before the first frame is decoded. Use Jellyfin's
            // mediaStreams metadata for detection (available before decode).
            let detectedFormat = detectVideoFormat(from: source)
            if detectedFormat != .sdr {
                // If content is DV but TV only supports HDR10, use HDR10 criteria
                let displayFormat: VideoFormat
                if detectedFormat == .dolbyVision && !DisplayCapabilities.supportsDolbyVision {
                    displayFormat = .hdr10
                } else {
                    displayFormat = detectedFormat
                }
                applyDisplayCriteria(format: displayFormat)
                // Give the TV time to begin the mode switch, then wait for completion
                try? await Task.sleep(for: .milliseconds(200))
                await waitForDisplayModeSwitch()
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
                    if self.showControls { self.scheduleControlsHide() }
                case .paused:
                    self.isLoading = false
                    self.isPlaying = false
                case .idle:
                    self.isPlaying = false
                    #if DEBUG
                    print("[NextEpisode] State=idle, hasStarted=\(self.hasStartedPlaying), nextEp=\(self.nextEpisode?.name ?? "nil")")
                    #endif
                    // If countdown didn't start yet (e.g. very short video),
                    // auto-play immediately on EOF
                    if self.hasStartedPlaying, self.nextEpisode != nil, !self.nextEpisodeCancelled, self.nextEpisodeTimer == nil {
                        Task { @MainActor [weak self] in
                            await self?.playNextEpisode()
                        }
                    }
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
                self.checkForNextEpisode()
                let dur = self.effectiveDuration
                let remaining = dur - time
                if self.nextEpisode != nil && !self.nextEpisodeCancelled && dur > 0 && remaining > 0 {
                    // Show overlay at 30s remaining
                    if !self.showNextEpisodeOverlay && remaining < 30 {
                        self.showNextEpisodeOverlay = true
                    }
                    // Start countdown at 10s remaining (plays to the end)
                    if self.nextEpisodeCountdown == 10 && remaining < 10 && self.nextEpisodeTimer == nil && self.showNextEpisodeOverlay {
                        self.startNextEpisodeCountdown()
                    }
                }
                guard !self.isScrubbing else { return }
                self.currentTime = self.formatSeconds(time)
                let rem = dur - time
                self.remainingTime = rem > 0 ? "-\(self.formatSeconds(rem))" : "-00:00"
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

        player.$videoFormat
            .receive(on: DispatchQueue.main)
            .sink { [weak self] format in
                self?.videoFormat = format
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

    // MARK: - Helpers

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

    /// Detect video format from Jellyfin MediaSource metadata.
    /// Available before player.load() — no decode needed.
    private func detectVideoFormat(from source: PlaybackMediaSource) -> VideoFormat {
        guard let videoStream = source.mediaStreams?.first(where: { $0.type == .video }) else {
            return .sdr
        }

        // videoRangeType is more specific: "DOVI", "HDR10", "HDR10Plus", "HLG"
        if let rangeType = videoStream.videoRangeType?.uppercased() {
            if rangeType.contains("DOVI") || rangeType.contains("DOV") { return .dolbyVision }
            if rangeType.contains("HDR10") { return .hdr10 }
            if rangeType.contains("HLG") { return .hlg }
        }

        // Fallback: videoRange is "HDR" or "SDR"
        if videoStream.videoRange?.uppercased() == "HDR" { return .hdr10 }

        return .sdr
    }

    func formatSeconds(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Display Mode Switching (tvOS)

    /// Tell tvOS to switch the TV to HDR/DV/HLG mode via AVDisplayCriteria.
    /// Must be called BEFORE playback starts so the TV has time to switch.
    /// Uses public AVKit API — `UIWindow.avDisplayManager` (tvOS 11.2+).
    func applyDisplayCriteria(format: VideoFormat, refreshRate: Float = 23.976) {
        #if os(tvOS)
        guard #available(tvOS 17.0, *), format != .sdr else { return }

        guard let window = displayWindow else {
            #if DEBUG
            print("[PlayerVM] No window for display criteria")
            #endif
            return
        }

        let displayManager = window.avDisplayManager

        // Respect user's "Match Content" setting
        guard displayManager.isDisplayCriteriaMatchingEnabled else {
            #if DEBUG
            print("[PlayerVM] Match Content disabled by user")
            #endif
            return
        }

        let transferFunction: CFString = switch format {
        case .hlg: kCVImageBufferTransferFunction_ITU_R_2100_HLG
        default:   kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        }

        let extensions: NSDictionary = [
            kCMFormatDescriptionExtension_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_TransferFunction: transferFunction,
            kCMFormatDescriptionExtension_YCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_2020,
        ]

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_HEVC,
            width: 3840, height: 2160,
            extensions: extensions,
            formatDescriptionOut: &formatDesc
        )
        guard let desc = formatDesc else { return }

        let criteria = AVDisplayCriteria(refreshRate: refreshRate, formatDescription: desc)
        displayManager.preferredDisplayCriteria = criteria

        #if DEBUG
        print("[PlayerVM] Display criteria SET: \(format), \(refreshRate) fps")
        #endif
        #endif
    }

    /// Wait for the TV to finish switching display modes before starting playback.
    func waitForDisplayModeSwitch() async {
        #if os(tvOS)
        guard let window = displayWindow else { return }
        let displayManager = window.avDisplayManager
        guard displayManager.isDisplayModeSwitchInProgress else { return }

        #if DEBUG
        print("[PlayerVM] Waiting for display mode switch...")
        #endif

        // Wait up to 5 seconds for the switch, checking periodically
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if !displayManager.isDisplayModeSwitchInProgress { break }
        }

        #if DEBUG
        print("[PlayerVM] Display mode switch completed")
        #endif
        #endif
    }

    func resetDisplayCriteria() {
        #if os(tvOS)
        guard let window = displayWindow else { return }
        window.avDisplayManager.preferredDisplayCriteria = nil
        #if DEBUG
        print("[PlayerVM] Display criteria RESET")
        #endif
        #endif
    }

    #if os(tvOS)
    private var displayWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
    }
    #endif
}

enum PlayerEngineError: LocalizedError {
    case noSource
    case noURL

    var errorDescription: String? {
        switch self {
        case .noSource: "No media source available"
        case .noURL: "Could not build stream URL"
        }
    }
}
