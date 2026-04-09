import AVFoundation
import Observation
import TVVLCKit

@Observable
@MainActor
final class PlayerViewModel {
    var isLoading = true
    var errorMessage: String?
    var engine: PlayerEngine?
    var isPlaying = false
    var showControls = false

    // VLCKit specific
    var currentTime: String = "00:00"
    var totalTime: String = "00:00"
    var progress: Float = 0
    var audioTracks: [(index: Int, name: String)] = []
    var subtitleTracks: [(index: Int, name: String)] = []
    var currentAudioIndex: Int = -1
    var currentSubtitleIndex: Int = -1

    let item: JellyfinItem
    let startFromBeginning: Bool
    let coordinator: PlaybackCoordinator

    private let playbackService: JellyfinPlaybackServiceProtocol
    private var progressTimer: Task<Void, Never>?
    private var controlsTimer: Task<Void, Never>?
    private var avPlayerObserver: Any?
    private var hasReportedStart = false

    init(
        item: JellyfinItem,
        startFromBeginning: Bool,
        playbackService: JellyfinPlaybackServiceProtocol,
        userID: String
    ) {
        self.item = item
        self.startFromBeginning = startFromBeginning
        self.playbackService = playbackService
        self.coordinator = PlaybackCoordinator(playbackService: playbackService, userID: userID)
        setupVLCCallbacks()
    }

    // MARK: - Lifecycle

    func startPlayback() async {
        isLoading = true
        errorMessage = nil

        do {
            try await coordinator.preparePlayback(item: item, startFromBeginning: startFromBeginning)
            engine = coordinator.engine

            if engine == .avPlayer {
                setupAVPlayerObservers()
            }

            await reportStart()
            startProgressReporting()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func stopPlayback() async {
        stopProgressReporting()
        removeAVPlayerObservers()
        await reportStop()
        coordinator.stop()
    }

    // MARK: - Controls

    func togglePlayPause() {
        coordinator.togglePlayPause()
        if engine == .vlcKit { showControlsTemporarily() }
    }

    func seekForward() {
        coordinator.seekForward(10)
        if engine == .vlcKit { showControlsTemporarily() }
    }

    func seekBackward() {
        coordinator.seekBackward(10)
        if engine == .vlcKit { showControlsTemporarily() }
    }

    func setAudioTrack(_ index: Int) {
        guard engine == .vlcKit else { return }
        coordinator.vlcPlayer.currentAudioTrackIndex = Int32(index)
        currentAudioIndex = index
    }

    func setSubtitleTrack(_ index: Int) {
        guard engine == .vlcKit else { return }
        coordinator.vlcPlayer.currentVideoSubTitleIndex = Int32(index)
        currentSubtitleIndex = index
    }

    func showControlsTemporarily() {
        showControls = true
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }

    // MARK: - AVPlayer Observers

    private func setupAVPlayerObservers() {
        // Periodic time observer
        avPlayerObserver = coordinator.avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 2),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let status = self.coordinator.avPlayer.timeControlStatus
            if status == .playing && self.isLoading {
                self.isLoading = false
                self.isPlaying = true
            }
            self.isPlaying = status == .playing
        }
    }

    private func removeAVPlayerObservers() {
        if let observer = avPlayerObserver {
            coordinator.avPlayer.removeTimeObserver(observer)
            avPlayerObserver = nil
        }
    }

    // MARK: - VLCKit Callbacks

    private func setupVLCCallbacks() {
        coordinator.onVLCStateChanged = { [weak self] state in
            guard let self, self.engine == .vlcKit else { return }
            switch state {
            case .playing:
                isLoading = false
                isPlaying = true
                audioTracks = coordinator.vlcAudioTracks
                subtitleTracks = coordinator.vlcSubtitleTracks
            case .paused:
                isPlaying = false
            case .ended, .stopped:
                isPlaying = false
            case .error:
                errorMessage = "Playback error"
                isLoading = false
            default:
                break
            }
        }

        coordinator.onVLCTimeChanged = { [weak self] ticks in
            guard let self, self.engine == .vlcKit else { return }
            if isLoading && ticks > 0 {
                isLoading = false
                isPlaying = true
                audioTracks = coordinator.vlcAudioTracks
                subtitleTracks = coordinator.vlcSubtitleTracks
                showControlsTemporarily()
            }
            progress = coordinator.vlcPlayer.position
            currentTime = formatTicks(ticks)
            let dur = Int64(coordinator.vlcPlayer.media?.length.intValue ?? 0) * 10_000
            if dur > 0 { totalTime = formatTicks(dur) }
        }

        coordinator.onVLCEndReached = { [weak self] in
            self?.isPlaying = false
        }
    }

    private func formatTicks(_ ticks: Int64) -> String {
        let totalSeconds = Int(ticks / 10_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Session Reporting

    private func reportStart() async {
        guard !hasReportedStart else { return }
        hasReportedStart = true
        let report = PlaybackStartReport(
            itemId: item.id, mediaSourceId: coordinator.mediaSourceID,
            playSessionId: coordinator.playSessionID,
            positionTicks: coordinator.currentPositionTicks,
            canSeek: true, playMethod: coordinator.playMethod.rawValue,
            audioStreamIndex: nil, subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackStart(report)
    }

    private func reportProgress() async {
        let report = PlaybackProgressReport(
            itemId: item.id, mediaSourceId: coordinator.mediaSourceID,
            playSessionId: coordinator.playSessionID,
            positionTicks: coordinator.currentPositionTicks,
            isPaused: coordinator.isPaused, canSeek: true,
            playMethod: coordinator.playMethod.rawValue,
            audioStreamIndex: nil, subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackProgress(report)
    }

    private func reportStop() async {
        let report = PlaybackStopReport(
            itemId: item.id, mediaSourceId: coordinator.mediaSourceID,
            playSessionId: coordinator.playSessionID,
            positionTicks: coordinator.currentPositionTicks
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
        controlsTimer?.cancel()
        controlsTimer = nil
    }
}
