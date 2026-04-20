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
        case skipIntroButton
        case audioButton
        case subtitleButton
        case speedButton
    }

    enum TrackDropdown: Equatable {
        case none
        case audio(highlighted: Int)   // index into player.audioTracks
        case subtitle(highlighted: Int) // index into subtitle items (0=Off, 1..=tracks)
        case speed(highlighted: Int)    // index into PlayerViewModel.speedOptions
    }

    var isDropdownOpen: Bool { trackDropdown != .none }

    /// Playback speed choices. Native tvOS player uses the same stepped
    /// set — keeping it consistent with user expectations. Index 2 = 1.0×.
    static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    /// Index into `speedOptions` for the currently applied rate.
    var activeSpeedIndex: Int = 2

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
    var isCountdownActive = false
    var nextEpisodeTimer: Task<Void, Never>?
    var hasFetchedNextEpisode = false
    var nextEpisodeCancelled = false

    // Intro skip — populated from Jellyfin Media Segments / intro-skipper plugin
    var introSegment: MediaSegment?
    /// True while playbackTime is inside the intro range. UI shows the
    /// Skip Intro button whenever this is true, regardless of whether
    /// the transport controls are open.
    var isInsideIntro: Bool = false
    /// Set once per episode after an auto-skip fires — keeps the time
    /// subscriber from re-triggering the skip in the brief window before
    /// the seek actually moves currentTime past introEnd.
    var didAutoSkipCurrentIntro: Bool = false

    // MARK: - Dependencies

    var item: JellyfinItem
    let player: AetherEngine

    let playbackService: JellyfinPlaybackServiceProtocol
    let userID: String
    var startFromBeginning: Bool
    var cachedPlaybackInfo: PlaybackInfoResponse?
    let preferences: PlaybackPreferences

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

    init(
        item: JellyfinItem,
        startFromBeginning: Bool,
        playbackService: JellyfinPlaybackServiceProtocol,
        userID: String,
        preferences: PlaybackPreferences,
        cachedPlaybackInfo: PlaybackInfoResponse? = nil
    ) {
        self.item = item
        self.player = DependencyContainer.playerEngine
        self.startFromBeginning = startFromBeginning
        self.playbackService = playbackService
        self.userID = userID
        self.preferences = preferences
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

            // Filter subtitle streams:
            // 1. Exclude image-based formats (PGS, VOBSUB) — can't convert to text
            // 2. Drop forced tracks — they only cover foreign-dialogue
            //    segments inside an otherwise-understood audio track, so
            //    users rarely want them on; keeping them also poisons the
            //    preferred-language auto-select (a forced "deu" beats a
            //    full "deu" track if it comes first).
            // 3. Deduplicate same-language streams with no distinguishing metadata
            let imageCodecs: Set<String> = ["pgssub", "hdmv_pgs_subtitle", "dvd_subtitle", "dvdsub", "xsub", "vobsub"]
            let textStreams = source.mediaStreams?.filter { stream in
                guard stream.type == .subtitle else { return false }
                if let codec = stream.codec?.lowercased(), imageCodecs.contains(codec) {
                    return false
                }
                if stream.isForced == true { return false }
                // Some servers put "forced" in the title instead of the flag.
                if let title = stream.title?.lowercased(), title.contains("forced") {
                    return false
                }
                return true
            } ?? []

            // Deduplicate: if multiple streams share the same language and
            // neither has a distinguishing title (SDH, Forced, etc.),
            // keep only the first one.
            var seen = Set<String>()
            subtitleStreams = textStreams.filter { stream in
                let lang = stream.language ?? "und"
                let hasDescriptor = stream.isForced == true
                    || (stream.title?.lowercased()).map { t in
                        ["sdh", "commentary", "cc", "signs", "songs", "hearing", "forced", "musik", "music"].contains(where: { t.contains($0) })
                    } ?? false
                let key = hasDescriptor ? "\(lang)_\(stream.title ?? "")" : lang
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }

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
            //
            // If the display won't actually switch (Match Content disabled,
            // SDR panel, no window), we must tone-map HDR→SDR during decode.
            // Without tone-mapping, AVSampleBufferDisplayLayer shows black
            // because it can't map PQ values onto an SDR display.
            let detectedFormat = detectVideoFormat(from: source)
            var displayWillSwitchToHDR = false
            if detectedFormat != .sdr {
                // If content is DV but TV only supports HDR10, use HDR10 criteria
                let displayFormat: VideoFormat
                if detectedFormat == .dolbyVision && !DisplayCapabilities.supportsDolbyVision {
                    displayFormat = .hdr10
                } else {
                    displayFormat = detectedFormat
                }
                displayWillSwitchToHDR = applyDisplayCriteria(format: displayFormat)
                if displayWillSwitchToHDR {
                    // waitForDisplayModeSwitch() polls
                    // isDisplayModeSwitchInProgress every 100 ms and
                    // returns immediately when the flag is false. So
                    // if the TV is already in the target HDR mode (e.g.
                    // user just watched another HDR film) it costs us
                    // a single check, not the full pre-sleep + wait
                    // dance. The previous unconditional 200 ms sleep
                    // was paid even in that no-op case.
                    await waitForDisplayModeSwitch()
                }
            }

            // Tone-map when source is HDR but display stays in SDR.
            let tonemapHDRToSDR = detectedFormat != .sdr && !displayWillSwitchToHDR
            #if DEBUG
            if tonemapHDRToSDR {
                print("[PlayerVM] Tone-mapping HDR→SDR (display stays in SDR mode)")
            }
            #endif

            try await player.load(
                url: url,
                startPosition: startPos,
                tonemapHDRToSDR: tonemapHDRToSDR
            )

            totalTime = formatSeconds(effectiveDuration)
            // Audio track priority: preferred language → stream default → first.
            let preferredAudio = preferences.preferredAudioLanguage
            let chosenAudio = player.audioTracks.first(where: {
                preferredAudio != nil && $0.language == preferredAudio
            }) ?? player.audioTracks.first(where: { $0.isDefault })
              ?? player.audioTracks.first
            if let chosenAudio {
                activeAudioIndex = chosenAudio.id
                player.selectAudioTrack(index: chosenAudio.id)
            }

            // Subtitle preference: if the user picked a language, enable
            // the matching stream automatically. No preference → leave off.
            if let preferredSub = preferences.preferredSubtitleLanguage,
               let match = subtitleStreams.first(where: { $0.language == preferredSub }) {
                selectSubtitleTrack(id: match.index)
            }

            isLoading = false
            isPlaying = true

            startObserving()
            await reportStart()
            startProgressReporting()

            // Fetch intro marker in the background — don't block
            // playback start if the server is slow or doesn't expose
            // the endpoint. Once the marker lands the next time tick
            // will flip isInsideIntro on naturally.
            Task { [weak self] in await self?.loadIntroSegment() }

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func stopPlayback() async {
        stopProgressReporting()
        cancellables.removeAll()
        // Capture position synchronously, then stop the engine, then
        // report. The capture-then-stop order is critical: player.stop()
        // resets currentTime to 0, so we'd lose the position if we read
        // it inside reportStop after the stop. By passing the captured
        // ticks explicitly we keep the proven progress-sync correctness
        // of the old "report before stop" flow, while killing the
        // ~1-2s of trailing audio that the user heard during the
        // network round-trip.
        let finalTicks = currentPositionTicks
        player.stop()
        // Always revert the TV to SDR once playback ends. PlayerView's
        // onDisappear also calls this, but if the app is backgrounded or
        // the VC is torn down by other means, we still want the TV back in
        // SDR mode so menus don't stay in HDR.
        resetDisplayCriteria()
        await reportStop(positionTicks: finalTicks)
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
                    // Demux EOF — start 10s countdown for next episode.
                    // The demux reads ahead 15-20s, so player.$currentTime
                    // may never reach the final seconds (Combine only fires
                    // on value changes). Cap at 10 so the overlay text is
                    // always visible.
                    if self.hasStartedPlaying,
                       self.nextEpisode != nil,
                       !self.nextEpisodeCancelled,
                       self.nextEpisodeTimer == nil {
                        let remaining = self.effectiveDuration - self.playbackTime
                        self.nextEpisodeCountdown = min(10, max(1, Int(ceil(max(0, remaining)))))
                        self.showNextEpisodeOverlay = true
                        self.startNextEpisodeCountdown()
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
                self.updateIntroVisibility(time: time)
                self.checkForNextEpisode()
                let dur = self.effectiveDuration
                let remaining = dur - time
                if self.nextEpisode != nil && !self.nextEpisodeCancelled && dur > 0 && remaining > 0 {
                    // Show overlay at 30s remaining
                    if !self.showNextEpisodeOverlay && remaining < 30 {
                        self.showNextEpisodeOverlay = true
                    }
                    // Start countdown when ≤10s remaining (synced to actual remaining time)
                    if remaining <= 10 && self.nextEpisodeTimer == nil && self.showNextEpisodeOverlay {
                        self.nextEpisodeCountdown = max(1, Int(ceil(remaining)))
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
                guard let self else { return }
                // Only show the HDR badge if the display is actually in
                // HDR mode. When "Match Dynamic Range" is off, the TV
                // stays in SDR — showing "HDR10" would be misleading.
                #if os(tvOS)
                if format != .sdr {
                    let matchEnabled = self.displayWindow?.avDisplayManager
                        .isDisplayCriteriaMatchingEnabled ?? false
                    if !matchEnabled {
                        self.videoFormat = .sdr
                        return
                    }
                }
                #endif
                self.videoFormat = format
            }
            .store(in: &cancellables)
    }

    // MARK: - Controls

    func togglePlayPause() {
        player.togglePlayPause()
        reportProgressIfNeeded()
        showControls = true
        scheduleControlsHide()
    }

    /// Seek by the user's configured interval (5/10/15/30 s). The
    /// direction is +1 (right) or −1 (left). Wraps the seconds variant
    /// so the press handler doesn't need a Preferences lookup.
    func seekJumpByConfiguredInterval(direction: Int) {
        let interval = preferences.skipIntervalSeconds
        let signed = (direction < 0 ? -1 : 1) * interval
        seekJump(seconds: Double(signed))
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

    // MARK: - Intro Skip

    /// Called from the playback-time Combine subscription. Toggles
    /// `isInsideIntro` so the UI can show/hide the Skip Intro button
    /// without each caller recomputing the range.
    func updateIntroVisibility(time: Double) {
        guard let seg = introSegment else {
            if isInsideIntro { setInsideIntro(false) }
            return
        }
        // Plugin sometimes reports introStart=0 on episodes with a
        // pre-title cold-open → button would pop up the instant the
        // episode starts, before the titles even play. Give it a tiny
        // lead-in so the button appears with the intro music.
        let inside = time >= max(seg.startSeconds, 0.5)
                  && time < seg.endSeconds - 1   // hide 1s before end

        // Auto-skip path: the very first tick inside the intro fires
        // the skip automatically if the user opted in. Guarded so the
        // skip only happens once per episode even as further ticks
        // arrive before currentTime has actually moved past introEnd.
        if inside && preferences.autoSkipIntro && !didAutoSkipCurrentIntro {
            didAutoSkipCurrentIntro = true
            skipIntro()
            return
        }

        if inside != isInsideIntro {
            setInsideIntro(inside)
        }
    }

    /// Update the flag *and* move focus away from the Skip Intro button
    /// if it just disappeared — otherwise the user would be stuck on a
    /// button that's no longer in the row.
    private func setInsideIntro(_ newValue: Bool) {
        isInsideIntro = newValue
        if !newValue && controlsFocus == .skipIntroButton {
            if !player.audioTracks.isEmpty { controlsFocus = .audioButton }
            else if !subtitleStreams.isEmpty { controlsFocus = .subtitleButton }
            else { controlsFocus = .speedButton }
        }
    }

    /// Jump past the intro. Triggered by the Skip Intro button.
    func skipIntro() {
        guard let seg = introSegment else { return }
        isInsideIntro = false
        Task { await player.seek(to: seg.endSeconds) }
    }

    /// Fetch the intro marker once on startup. Safe if the server
    /// doesn't expose the endpoint — service returns nil and the
    /// button simply never appears.
    func loadIntroSegment() async {
        didAutoSkipCurrentIntro = false
        do {
            introSegment = try await playbackService.getIntroSegment(itemID: item.id)
        } catch {
            #if DEBUG
            print("[IntroSkip] Fetch failed: \(error)")
            #endif
            introSegment = nil
        }
    }

    /// Apply the playback speed at the given index in `speedOptions`.
    func selectSpeed(index: Int) {
        let clamped = max(0, min(Self.speedOptions.count - 1, index))
        activeSpeedIndex = clamped
        player.setRate(Self.speedOptions[clamped])
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

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else { return }
            subtitleCues = SRTParser.parse(content)
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
    ///
    /// - Returns: `true` if the display will switch to HDR mode. `false` means
    ///   the caller should tone-map HDR content down to SDR during decode
    ///   (e.g. Match Content disabled, no window, or SDR content).
    @discardableResult
    func applyDisplayCriteria(format: VideoFormat, refreshRate: Float = 23.976) -> Bool {
        #if os(tvOS)
        guard #available(tvOS 17.0, *), format != .sdr else { return false }

        guard let window = displayWindow else {
            #if DEBUG
            print("[PlayerVM] No window for display criteria")
            #endif
            return false
        }

        let displayManager = window.avDisplayManager

        // Respect user's "Match Content" setting
        guard displayManager.isDisplayCriteriaMatchingEnabled else {
            return false
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
        guard let desc = formatDesc else { return false }

        let criteria = AVDisplayCriteria(refreshRate: refreshRate, formatDescription: desc)
        displayManager.preferredDisplayCriteria = criteria

        #if DEBUG
        print("[PlayerVM] Display criteria SET: \(format), \(refreshRate) fps")
        #endif
        return true
        #else
        return false
        #endif
    }

    /// Wait for the TV to finish switching display modes before starting playback.
    func waitForDisplayModeSwitch() async {
        #if os(tvOS)
        guard let window = displayWindow else { return }
        let displayManager = window.avDisplayManager
        guard displayManager.isDisplayModeSwitchInProgress else { return }

        // Wait up to 5 seconds for the switch, checking periodically
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if !displayManager.isDisplayModeSwitchInProgress { break }
        }
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
