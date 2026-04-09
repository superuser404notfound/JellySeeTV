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

    // MARK: - Load and Play

    func load(url: URL, startPosition: Double? = nil) async throws {
        state = .loading

        // 1. Open demuxer
        let dmx = Demuxer()
        try dmx.open(url: url)
        demuxer = dmx
        duration = dmx.duration

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

        // 3. Create video decoder
        var vDecoder: VideoDecoder? = nil
        if dmx.videoStreamIndex >= 0,
           let codecPar = dmx.codecParameters(for: dmx.videoStreamIndex) {
            vDecoder = try VideoDecoder(codecParameters: codecPar)
        }
        videoDecoder = vDecoder

        // 4. Create audio decoder + output
        var aDecoder: AudioDecoder? = nil
        let aOutput = AudioOutput()
        if dmx.audioStreamIndex >= 0,
           let codecPar = dmx.codecParameters(for: dmx.audioStreamIndex) {
            do {
                aDecoder = try AudioDecoder(codecParameters: codecPar)
                if let format = aDecoder?.audioFormat {
                    let startPTS = startPosition ?? 0
                    try aOutput.start(format: format, startPTS: startPTS)
                } else {
                    #if DEBUG
                    print("[PlayerEngine] WARNING: AudioDecoder has no audioFormat")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[PlayerEngine] Audio init error: \(error)")
                #endif
                // Continue without audio
            }
        }
        audioDecoder = aDecoder
        audioOutput = aOutput

        // 5. Seek to start position if needed
        if let pos = startPosition, pos > 0 {
            try dmx.seek(to: pos)
        }

        // 6. Create buffer coordinator and wire up callbacks
        let coordinator = BufferCoordinator(
            demuxer: dmx,
            videoDecoder: vDecoder,
            audioDecoder: aDecoder,
            audioOutput: aOutput
        )
        bufferCoordinator = coordinator

        coordinator.onVideoFrame = { [weak self] frame in
            self?.videoRenderer.enqueue(
                pixelBuffer: frame.pixelBuffer,
                pts: frame.pts,
                duration: frame.duration
            )
        }

        coordinator.onEndOfFile = { [weak self] in
            self?.state = .idle
        }

        coordinator.onError = { [weak self] msg in
            self?.state = .error(msg)
        }

        // 7. Start pipeline
        coordinator.start()
        state = .playing
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

    func seek(to seconds: Double) async {
        let prevState = state
        state = .seeking
        do {
            try bufferCoordinator?.seek(to: max(0, min(seconds, duration)))
            videoRenderer.flush()
        } catch {
            #if DEBUG
            print("[PlayerEngine] Seek error: \(error)")
            #endif
        }
        state = prevState == .paused ? .paused : .playing
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
                    currentTime = clock.currentTime
                    if duration > 0 {
                        progress = Float(currentTime / duration)
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
