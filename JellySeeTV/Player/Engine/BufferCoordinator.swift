import Foundation
#if !targetEnvironment(simulator)
import CFFmpeg

/// Orchestrates the entire playback pipeline.
/// Runs entirely off-MainActor on background threads.
nonisolated final class BufferCoordinator: @unchecked Sendable {
    nonisolated(unsafe) let demuxer: Demuxer
    nonisolated(unsafe) let videoDecoder: VideoDecoder?
    nonisolated(unsafe) let audioDecoder: AudioDecoder?
    nonisolated(unsafe) let audioOutput: AudioOutput
    nonisolated(unsafe) let videoRenderer: VideoRenderer
    nonisolated(unsafe) let syncClock: SyncClock

    nonisolated(unsafe) let videoQueue = PacketQueue(capacity: 200)
    nonisolated(unsafe) let audioQueue = PacketQueue(capacity: 400)

    nonisolated(unsafe) var onEndOfFile: (() -> Void)?
    nonisolated(unsafe) var onError: ((String) -> Void)?

    nonisolated(unsafe) private var demuxTask: Task<Void, Never>?
    nonisolated(unsafe) private var videoDecodeTask: Task<Void, Never>?
    nonisolated(unsafe) private var audioDecodeTask: Task<Void, Never>?
    nonisolated(unsafe) private var isRunning = false
    nonisolated(unsafe) private var isEOF = false

    init(demuxer: Demuxer, videoDecoder: VideoDecoder?, audioDecoder: AudioDecoder?, audioOutput: AudioOutput, videoRenderer: VideoRenderer) {
        self.demuxer = demuxer
        self.videoDecoder = videoDecoder
        self.audioDecoder = audioDecoder
        self.audioOutput = audioOutput
        self.videoRenderer = videoRenderer
        self.syncClock = SyncClock(audioOutput: audioOutput)
    }

    func start() {
        isRunning = true
        isEOF = false
        videoQueue.reset()
        audioQueue.reset()

        demuxTask = Task.detached(priority: .userInitiated) { [self] in
            self.demuxLoop()
        }
        audioDecodeTask = Task.detached(priority: .high) { [self] in
            self.audioDecodeLoop()
        }
        videoDecodeTask = Task.detached(priority: .high) { [self] in
            self.videoDecodeLoop()
        }
    }

    func stop() {
        isRunning = false
        // Interrupt any in-progress FFmpeg I/O so the demux loop can exit
        demuxer.interruptIO()
        videoQueue.flush()
        audioQueue.flush()
        demuxTask?.cancel()
        videoDecodeTask?.cancel()
        audioDecodeTask?.cancel()
        audioOutput.stop()
    }

    /// Asynchronous variant that waits for all decode loops to actually exit.
    /// Call this before closing the demuxer to avoid use-after-free crashes.
    func stopAndWait() async {
        stop()
        // Await each task to make sure the loops have fully unwound
        await demuxTask?.value
        await videoDecodeTask?.value
        await audioDecodeTask?.value
    }

    func pause() { audioOutput.pause() }
    func resume() { audioOutput.resume() }

    func seek(to seconds: Double) throws {
        #if DEBUG
        print("[BufferCoordinator] Seek to \(String(format: "%.1f", seconds))s")
        #endif

        // 1. Stop audio playback to prevent glitches
        audioOutput.flush()

        // 2. Flush queues so decode loops don't process stale packets
        videoQueue.flush()
        audioQueue.flush()

        // 3. Flush decoders to clear internal buffered frames
        _ = videoDecoder?.flush()
        _ = audioDecoder?.flush()

        // 4. Seek the demuxer to nearest keyframe
        try demuxer.seek(to: seconds)

        // 5. Reset queues (unset flushed flag so enqueue/dequeue work again)
        videoQueue.reset()
        audioQueue.reset()

        // 6. Restart audio from new position
        audioOutput.restartAfterFlush(startPTS: seconds)

        #if DEBUG
        print("[BufferCoordinator] Seek complete, audio restarted at \(String(format: "%.1f", seconds))s")
        #endif
    }

    // MARK: - Loops (all run on background threads)

    private func demuxLoop() {
        while isRunning {
            guard let packet = demuxer.readPacket() else {
                isEOF = true
                let callback = onEndOfFile
                DispatchQueue.main.async { callback?() }
                return
            }
            switch packet.streamType {
            case .video: videoQueue.enqueue(packet)
            case .audio: audioQueue.enqueue(packet)
            case .subtitle: break
            }
        }
    }

    nonisolated(unsafe) private var audioFrameCount = 0
    nonisolated(unsafe) private var videoFrameCount = 0
    /// When set, the video loop displays the next decoded frame immediately
    /// (bypassing sync clock). Used after seek-while-paused so the user sees
    /// the new position even though playback hasn't resumed yet.
    nonisolated(unsafe) var forceDisplayNextFrame = false
    #if DEBUG
    nonisolated(unsafe) private var displayedCount = 0
    nonisolated(unsafe) private var droppedCount = 0
    #endif

    private func audioDecodeLoop() {
        guard let decoder = audioDecoder else {
            #if DEBUG
            print("[Audio Loop] No decoder, exiting")
            #endif
            return
        }
        #if DEBUG
        print("[Audio Loop] Started")
        #endif
        while isRunning {
            guard let packet = audioQueue.dequeue(timeout: 0.05) else {
                if isEOF && audioQueue.isEmpty {
                    #if DEBUG
                    print("[Audio Loop] EOF, decoded \(audioFrameCount) frames")
                    #endif
                    return
                }
                continue
            }
            guard let avPkt = packet.avPacket else { continue }
            let frames = decoder.decode(packet: avPkt)
            for frame in frames {
                audioOutput.scheduleBuffer(frame.pcmBuffer)
                audioFrameCount += 1
            }
            #if DEBUG
            if audioFrameCount > 0 && audioFrameCount % 100 == 0 {
                print("[Audio Loop] Decoded \(audioFrameCount) frames, queue: \(audioQueue.count)")
            }
            #endif
        }
        #if DEBUG
        print("[Audio Loop] Stopped, decoded \(audioFrameCount) frames")
        #endif
    }

    private func videoDecodeLoop() {
        guard let decoder = videoDecoder else {
            #if DEBUG
            print("[Video Loop] No decoder, exiting")
            #endif
            return
        }
        #if DEBUG
        print("[Video Loop] Started")
        #endif
        while isRunning {
            // While paused, only proceed if we need to force-display next frame
            while syncClock.isPaused && !forceDisplayNextFrame && isRunning {
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let packet = videoQueue.dequeue(timeout: 0.05) else {
                if isEOF && videoQueue.isEmpty {
                    #if DEBUG
                    print("[Video Loop] EOF, decoded \(videoFrameCount) frames")
                    #endif
                    return
                }
                continue
            }
            guard let avPkt = packet.avPacket else { continue }
            let frames = decoder.decode(packet: avPkt)
            for frame in frames {
                displayWithSync(frame)
                videoFrameCount += 1
            }
            #if DEBUG
            if videoFrameCount > 0 && videoFrameCount % 50 == 0 {
                print("[Video Loop] Decoded \(videoFrameCount) frames, queue: \(videoQueue.count), clock: \(String(format: "%.1f", syncClock.currentTime))s")
            }
            #endif
        }
        #if DEBUG
        print("[Video Loop] Stopped, decoded \(videoFrameCount) frames")
        #endif
    }

    private func displayWithSync(_ frame: DecodedVideoFrame) {
        // If we're forcing a frame display (e.g. first frame after seek-while-paused),
        // bypass sync entirely
        if forceDisplayNextFrame {
            videoRenderer.display(pixelBuffer: frame.pixelBuffer, pts: frame.pts)
            forceDisplayNextFrame = false
            #if DEBUG
            print("[Sync] FORCED DISPLAY pts=\(String(format: "%.3f", frame.pts))")
            #endif
            return
        }

        while isRunning {
            switch syncClock.shouldDisplay(framePTS: frame.pts) {
            case .display:
                videoRenderer.display(pixelBuffer: frame.pixelBuffer, pts: frame.pts)
                #if DEBUG
                displayedCount += 1
                if displayedCount == 1 || displayedCount % 500 == 0 {
                    print("[Sync] DISPLAY #\(displayedCount) pts=\(String(format: "%.3f", frame.pts)) clock=\(String(format: "%.3f", syncClock.currentTime))")
                }
                #endif
                return
            case .drop:
                #if DEBUG
                droppedCount += 1
                if droppedCount <= 3 || droppedCount % 500 == 0 {
                    print("[Sync] DROP #\(droppedCount) pts=\(String(format: "%.3f", frame.pts)) clock=\(String(format: "%.3f", syncClock.currentTime))")
                }
                #endif
                return
            case .wait(let seconds):
                Thread.sleep(forTimeInterval: min(seconds, 0.05))
            }
        }
    }
}

#endif
