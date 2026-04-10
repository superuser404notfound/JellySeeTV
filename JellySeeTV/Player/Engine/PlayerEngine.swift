import Foundation
import Observation
#if !targetEnvironment(simulator)
import CFFmpeg

/// The state of the player engine
enum EngineState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case seeking
    case error(String)
}

/// Custom video player engine: FFmpeg demuxing → VideoToolbox decode → AVSampleBufferDisplayLayer.
/// Replaces AVPlayer and VLCKit with a fully custom pipeline for instant DirectPlay.
@Observable
@MainActor
final class PlayerEngine {
    // Public state
    var state: EngineState = .idle
    var currentTime: Double = 0
    var duration: Double = 0
    var progress: Float = 0
    var audioTracks: [TrackInfo] = []
    var subtitleTracks: [TrackInfo] = []
    var currentAudioTrackIndex: Int = 0

    // Components
    let videoRenderer = VideoRenderer()
    private var demuxer: Demuxer?
    private var videoDecoder: VideoDecoder?
    private var audioDecoder: AudioDecoder?
    private var audioOutput: AudioOutput?
    private var bufferCoordinator: BufferCoordinator?
    private var timeUpdateTask: Task<Void, Never>?

    // Source URL — kept so we can reopen the stream for seeking
    private var sourceURL: URL?
    /// Time offset added to the audio clock for display purposes.
    /// When seeking via Jellyfin StartTimeTicks, the new stream's PTS is 0-based,
    /// so we add this offset to show the user the actual position in the file.
    private var displayTimeOffset: Double = 0
    /// Original media duration (preserved across seeks since the seeked stream
    /// reports a different/zero duration).
    private var originalDuration: Double = 0
    /// Prevents concurrent seek operations from interfering.
    private var isSeekInProgress = false

    // MARK: - Load and Play

    /// Load a media URL. Pass a pre-opened `cachedDemuxer` for instant start.
    /// `streamAlreadyAtPosition`: if true, the URL already includes a server-side
    /// time offset (e.g., StartTimeTicks), so we skip the FFmpeg seek call.
    func load(url: URL, startPosition: Double? = nil, cachedDemuxer: Demuxer? = nil, streamAlreadyAtPosition: Bool = false, startPaused: Bool = false) async throws {
        state = .loading
        // Only update sourceURL on initial load (not on seek-by-reload)
        if !streamAlreadyAtPosition {
            sourceURL = url
            displayTimeOffset = 0
            originalDuration = 0
        }

        #if DEBUG
        let loadStart = CFAbsoluteTimeGetCurrent()
        #endif

        // 1. Use pre-opened demuxer or open fresh (off main thread)
        let dmx: Demuxer
        if let cached = cachedDemuxer {
            dmx = cached
            #if DEBUG
            print("[PlayerEngine] Using pre-opened demuxer")
            #endif
        } else {
            dmx = Demuxer()
            try await Task.detached {
                try dmx.open(url: url, skipProbe: true)
            }.value
        }
        demuxer = dmx
        duration = dmx.duration
        // Remember the original duration on first load
        if originalDuration == 0 && dmx.duration > 0 {
            originalDuration = dmx.duration
        }

        // 2. Extract track info
        audioTracks = dmx.audioStreams.map { stream in
            TrackInfo(
                id: Int(stream.index),
                name: stream.title ?? stream.language ?? "Track \(stream.index)",
                codec: stream.codecName,
                language: stream.language,
                isDefault: stream.isDefault
            )
        }
        subtitleTracks = dmx.subtitleStreams.map { stream in
            TrackInfo(
                id: Int(stream.index),
                name: stream.title ?? stream.language ?? "Track \(stream.index)",
                codec: stream.codecName,
                language: stream.language,
                isDefault: stream.isDefault
            )
        }

        // 3. Create decoders (video + audio in parallel where possible)
        var vDecoder: VideoDecoder? = nil
        if dmx.videoStreamIndex >= 0,
           let codecPar = dmx.codecParameters(for: dmx.videoStreamIndex) {
            let vtb = dmx.timeBase(for: dmx.videoStreamIndex)
            vDecoder = try VideoDecoder(codecParameters: codecPar, streamTimeBase: vtb)
        }
        videoDecoder = vDecoder

        var aDecoder: AudioDecoder? = nil
        let aOutput = AudioOutput()
        if dmx.audioStreamIndex >= 0,
           let codecPar = dmx.codecParameters(for: dmx.audioStreamIndex) {
            do {
                let atb = dmx.timeBase(for: dmx.audioStreamIndex)
                aDecoder = try AudioDecoder(codecParameters: codecPar, streamTimeBase: atb)
                if let format = aDecoder?.audioFormat {
                    let startPTS = startPosition ?? 0
                    try aOutput.start(format: format, startPTS: startPTS)
                }
            } catch {
                #if DEBUG
                print("[PlayerEngine] Audio init error: \(error)")
                #endif
            }
        }
        audioDecoder = aDecoder
        audioOutput = aOutput

        // 4. Seek to start position if needed (skip if URL already has it)
        if let pos = startPosition, pos > 0, !streamAlreadyAtPosition {
            try dmx.seek(to: pos)
        }

        #if DEBUG
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        print("[PlayerEngine] Total load time: \(String(format: "%.3f", loadTime))s")
        #endif

        // 6. Create buffer coordinator (renderer called directly from decode thread)
        let coordinator = BufferCoordinator(
            demuxer: dmx,
            videoDecoder: vDecoder,
            audioDecoder: aDecoder,
            audioOutput: aOutput,
            videoRenderer: videoRenderer
        )
        bufferCoordinator = coordinator

        coordinator.onEndOfFile = { [weak self] in
            self?.state = .idle
        }

        coordinator.onError = { [weak self] msg in
            self?.state = .error(msg)
        }

        // 7. Start pipeline
        coordinator.start()
        if startPaused {
            coordinator.pause()
            state = .paused
        } else {
            state = .playing
        }
        startTimeUpdates()

        #if DEBUG
        print("[PlayerEngine] Started: \(url.lastPathComponent)")
        print("[PlayerEngine] Duration: \(String(format: "%.1f", duration))s")
        print("[PlayerEngine] Video: \(vDecoder != nil ? "yes" : "no"), Audio: \(aDecoder != nil ? "yes" : "no")")
        print("[PlayerEngine] Audio tracks: \(audioTracks.count), Subtitle tracks: \(subtitleTracks.count)")
        #endif
    }

    // MARK: - Playback Controls

    func play() {
        bufferCoordinator?.resume()
        state = .playing
    }

    func pause() {
        bufferCoordinator?.pause()
        state = .paused
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: play()
        default: break
        }
    }

    /// Seek by reopening the stream with Jellyfin's StartTimeTicks parameter.
    /// Jellyfin remuxes the stream and emits PTS values starting at 0, so we
    /// keep the audio clock 0-based and add a displayTimeOffset for the UI.
    func seek(to seconds: Double) async {
        guard let url = sourceURL else { return }
        guard !isSeekInProgress else {
            #if DEBUG
            print("[PlayerEngine] Seek already in progress, ignoring")
            #endif
            return
        }
        isSeekInProgress = true
        defer { isSeekInProgress = false }

        // Clamp to known duration if available
        let target: Double
        let knownDuration = (duration > 0) ? duration : originalDuration
        if knownDuration > 0 {
            target = max(0, min(seconds, knownDuration))
        } else {
            target = max(0, seconds)
        }

        #if DEBUG
        print("[PlayerEngine] Seek (reload) to \(String(format: "%.1f", target))s")
        let seekStart = CFAbsoluteTimeGetCurrent()
        #endif

        state = .seeking

        // Strip any existing StartTimeTicks before adding the new one
        let baseURL = stripStartTimeTicks(from: url)
        let seekURL = appendStartTimeTicks(to: baseURL, seconds: target)

        // Stop the current pipeline cleanly (sync, all loops will exit)
        await tearDownPipeline()

        // Open fresh pipeline. The new stream is 0-based, so:
        //  - audioOutput.startPTS = 0 (don't pass startPosition)
        //  - displayTimeOffset = target (added when reading time for UI/sync clock)
        displayTimeOffset = target
        do {
            // After seek, start paused — user must click to resume
            try await load(url: seekURL, startPosition: nil, streamAlreadyAtPosition: true, startPaused: true)
            // Force display the first frame so user sees the new position
            bufferCoordinator?.forceDisplayNextFrame = true
            // Restore the original duration so progress bar still works
            if originalDuration > 0 {
                duration = originalDuration
            }
            #if DEBUG
            let elapsed = CFAbsoluteTimeGetCurrent() - seekStart
            print("[PlayerEngine] Seek complete in \(String(format: "%.3f", elapsed))s, displayOffset=\(target)")
            #endif
        } catch {
            #if DEBUG
            print("[PlayerEngine] Seek (reload) error: \(error)")
            #endif
            state = .error("Seek failed: \(error.localizedDescription)")
        }
    }

    /// Strip any existing StartTimeTicks query item from a URL.
    private func stripStartTimeTicks(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url
        }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "StartTimeTicks" }
        return components.url ?? url
    }

    /// Build a Jellyfin stream URL with the given start position as StartTimeTicks.
    private func appendStartTimeTicks(to url: URL, seconds: Double) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "StartTimeTicks" }
        let ticks = Int64(seconds * 10_000_000)
        queryItems.append(URLQueryItem(name: "StartTimeTicks", value: String(ticks)))
        components.queryItems = queryItems
        return components.url ?? url
    }

    /// Stop and clean up the current playback pipeline. Used before a seek-reload.
    private func tearDownPipeline() async {
        stopTimeUpdates()

        // 1. Stop audio output IMMEDIATELY to silence the speaker
        audioOutput?.stop()

        // 2. Stop the buffer coordinator and WAIT for all decode loops to exit
        //    This uses the FFmpeg interrupt callback to abort any blocked I/O
        await bufferCoordinator?.stopAndWait()

        // 3. Now safe to close decoders and demuxer (no concurrent access)
        videoDecoder?.close()
        audioDecoder?.close()
        demuxer?.close()

        bufferCoordinator = nil
        videoDecoder = nil
        audioDecoder = nil
        audioOutput = nil
        demuxer = nil
    }

    func stop() {
        stopTimeUpdates()
        bufferCoordinator?.stop()
        videoRenderer.flush()
        audioOutput?.stop()
        videoDecoder?.close()
        audioDecoder?.close()
        demuxer?.close()

        demuxer = nil
        videoDecoder = nil
        audioDecoder = nil
        audioOutput = nil
        bufferCoordinator = nil

        state = .idle
        currentTime = 0
        progress = 0
        displayTimeOffset = 0
        originalDuration = 0
        sourceURL = nil
    }

    // MARK: - Track Selection

    func selectAudioTrack(index: Int) async {
        guard let dmx = demuxer else { return }
        dmx.selectAudioStream(index: Int32(index))
        currentAudioTrackIndex = index

        // Reinit audio decoder with new stream
        if let codecPar = dmx.codecParameters(for: Int32(index)) {
            audioDecoder?.close()
            audioDecoder = try? AudioDecoder(codecParameters: codecPar)
        }
    }

    // MARK: - Time Updates

    private func startTimeUpdates() {
        timeUpdateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                if let clock = bufferCoordinator?.syncClock {
                    // Add displayTimeOffset for seek-by-reload (stream is 0-based)
                    currentTime = clock.currentTime + displayTimeOffset
                    let dur = (duration > 0) ? duration : originalDuration
                    if dur > 0 {
                        progress = Float(currentTime / dur)
                    }
                }
            }
        }
    }

    private func stopTimeUpdates() {
        timeUpdateTask?.cancel()
        timeUpdateTask = nil
    }
}

/// Info about an audio or subtitle track
struct TrackInfo: Identifiable, Sendable {
    let id: Int
    let name: String
    let codec: String
    let language: String?
    let isDefault: Bool
}

#else
// Simulator stub
@Observable
@MainActor
final class PlayerEngine {
    var state: String = "not available in simulator"
    var currentTime: Double = 0
    var duration: Double = 0
    var progress: Float = 0
    let videoRenderer = VideoRenderer()
    func load(url: URL, startPosition: Double? = nil) async throws {}
    func play() {}
    func pause() {}
    func togglePlayPause() {}
    func seek(to seconds: Double) async {}
    func stop() {}
}
struct TrackInfo: Identifiable, Sendable {
    let id: Int
    let name: String
    let codec: String
    let language: String?
    let isDefault: Bool
}
#endif
