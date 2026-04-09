import Foundation
#if !targetEnvironment(simulator)
import CFFmpeg

/// Orchestrates the entire playback pipeline:
/// Demuxer → PacketQueues → Decoders → AudioOutput/VideoRenderer
final class BufferCoordinator: @unchecked Sendable {
    let demuxer: Demuxer
    let videoDecoder: VideoDecoder?
    let audioDecoder: AudioDecoder?
    let audioOutput: AudioOutput
    let syncClock: SyncClock

    let videoQueue = PacketQueue(capacity: 200)
    let audioQueue = PacketQueue(capacity: 400)

    /// Callback: decoded video frame ready to display
    var onVideoFrame: ((DecodedVideoFrame) -> Void)?
    /// Callback: playback reached end of file
    var onEndOfFile: (() -> Void)?
    /// Callback: error occurred
    var onError: ((String) -> Void)?

    private var demuxTask: Task<Void, Never>?
    private var videoDecodeTask: Task<Void, Never>?
    private var audioDecodeTask: Task<Void, Never>?
    private var isRunning = false
    private var isEOF = false

    init(demuxer: Demuxer, videoDecoder: VideoDecoder?, audioDecoder: AudioDecoder?, audioOutput: AudioOutput) {
        self.demuxer = demuxer
        self.videoDecoder = videoDecoder
        self.audioDecoder = audioDecoder
        self.audioOutput = audioOutput
        self.syncClock = SyncClock(audioOutput: audioOutput)
    }

    // MARK: - Start Pipeline

    func start() {
        isRunning = true
        isEOF = false
        videoQueue.reset()
        audioQueue.reset()

        // Start demux loop (fills packet queues)
        demuxTask = Task.detached(priority: .userInitiated) { [weak self] in
            self?.demuxLoop()
        }

        // Start audio decode loop
        audioDecodeTask = Task.detached(priority: .high) { [weak self] in
            self?.audioDecodeLoop()
        }

        // Start video decode + sync loop
        videoDecodeTask = Task.detached(priority: .high) { [weak self] in
            self?.videoDecodeLoop()
        }
    }

    // MARK: - Stop

    func stop() {
        isRunning = false
        videoQueue.flush()
        audioQueue.flush()
        demuxTask?.cancel()
        videoDecodeTask?.cancel()
        audioDecodeTask?.cancel()
        audioOutput.stop()
    }

    // MARK: - Pause / Resume

    func pause() {
        audioOutput.pause()
    }

    func resume() {
        audioOutput.resume()
    }

    // MARK: - Seek

    func seek(to seconds: Double) throws {
        // 1. Pause audio
        audioOutput.flush()

        // 2. Flush queues
        videoQueue.flush()
        audioQueue.flush()

        // 3. Flush decoders
        _ = videoDecoder?.flush()
        _ = audioDecoder?.flush()

        // 4. Seek demuxer
        try demuxer.seek(to: seconds)

        // 5. Reset queues for new data
        videoQueue.reset()
        audioQueue.reset()

        // 6. Restart audio from new position
        audioOutput.restartAfterFlush(startPTS: seconds)

        #if DEBUG
        print("[BufferCoordinator] Seeked to \(String(format: "%.1f", seconds))s")
        #endif
    }

    // MARK: - Demux Loop

    private func demuxLoop() {
        while isRunning {
            guard let packet = demuxer.readPacket() else {
                // EOF
                isEOF = true
                Task { @MainActor in onEndOfFile?() }
                return
            }

            switch packet.streamType {
            case .video:
                videoQueue.enqueue(packet)
            case .audio:
                audioQueue.enqueue(packet)
            case .subtitle:
                // TODO Phase 7: subtitle handling
                break
            }
        }
    }

    // MARK: - Audio Decode Loop

    private func audioDecodeLoop() {
        guard let decoder = audioDecoder else { return }

        while isRunning {
            guard let packet = audioQueue.dequeue(timeout: 0.05) else {
                if isEOF && audioQueue.isEmpty { return }
                continue
            }

            let frames = decoder.decode(packet: packet.packet)
            for frame in frames {
                audioOutput.scheduleBuffer(frame.pcmBuffer)
            }
        }
    }

    // MARK: - Video Decode + Sync Loop

    private func videoDecodeLoop() {
        guard let decoder = videoDecoder else { return }

        while isRunning {
            // Wait if paused
            while syncClock.isPaused && isRunning {
                Thread.sleep(forTimeInterval: 0.01)
            }

            guard let packet = videoQueue.dequeue(timeout: 0.05) else {
                if isEOF && videoQueue.isEmpty { return }
                continue
            }

            let frames = decoder.decode(packet: packet.packet)
            for frame in frames {
                displayWithSync(frame)
            }
        }
    }

    /// Display a video frame respecting A/V sync
    private func displayWithSync(_ frame: DecodedVideoFrame) {
        while isRunning {
            let action = syncClock.shouldDisplay(framePTS: frame.pts)

            switch action {
            case .display:
                Task { @MainActor in onVideoFrame?(frame) }
                return
            case .drop:
                // Frame too late, skip
                return
            case .wait(let seconds):
                // Too early, sleep
                Thread.sleep(forTimeInterval: min(seconds, 0.05))
            }
        }
    }
}

#endif // !targetEnvironment(simulator)
