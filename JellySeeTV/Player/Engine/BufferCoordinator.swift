import Foundation
#if !targetEnvironment(simulator)
import CFFmpeg

/// Orchestrates the entire playback pipeline.
/// Components are reused across seeks — only the demuxer is replaced.
nonisolated final class BufferCoordinator: @unchecked Sendable {
    // Demuxer is mutable so we can swap it on seek (instead of recreating
    // the entire pipeline each time).
    nonisolated(unsafe) private(set) var demuxer: Demuxer
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

    /// When true, all decode loops pause and acknowledge via the *Paused flags.
    /// Used to synchronize the demuxer swap during seek.
    nonisolated(unsafe) private var isSeeking = false
    nonisolated(unsafe) private var demuxLoopPaused = false
    nonisolated(unsafe) private var videoLoopPaused = false
    nonisolated(unsafe) private var audioLoopPaused = false

    /// When set, the video loop displays the next decoded frame immediately
    /// (bypassing sync clock). Used after seek-while-paused so the user sees
    /// the new position even though playback hasn't resumed yet.
    nonisolated(unsafe) var forceDisplayNextFrame = false

    nonisolated(unsafe) private var audioFrameCount = 0
    nonisolated(unsafe) private var videoFrameCount = 0
    #if DEBUG
    nonisolated(unsafe) private var displayedCount = 0
    nonisolated(unsafe) private var droppedCount = 0
    #endif

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
        isSeeking = false
        // Interrupt any in-progress FFmpeg I/O so the demux loop can exit
        demuxer.interruptIO()
        videoQueue.flush()
        audioQueue.flush()
        demuxTask?.cancel()
        videoDecodeTask?.cancel()
        audioDecodeTask?.cancel()
        audioOutput.stop()
    }

    func stopAndWait() async {
        stop()
        await demuxTask?.value
        await videoDecodeTask?.value
        await audioDecodeTask?.value
    }

    func pause() { audioOutput.pause() }
    func resume() { audioOutput.resume() }

    // MARK: - Seek by Demuxer Replacement

    /// Replace the demuxer atomically, flushing all queues/decoders/audio.
    /// Reuses the existing decoders and audio output (no resource churn).
    func replaceDemuxer(_ newDemuxer: Demuxer, pauseAfter: Bool) async {
        #if DEBUG
        print("[BufferCoordinator] Replace demuxer (pauseAfter=\(pauseAfter))")
        #endif

        // 1. Signal all decode loops to pause
        isSeeking = true

        // 2. Interrupt the OLD demuxer's I/O so the demux loop can exit av_read_frame
        demuxer.interruptIO()

        // 3. Wake up the queues so any blocked dequeue() returns
        videoQueue.flush()
        audioQueue.flush()

        // 4. Wait until all loops have actually entered their paused state
        let deadline = Date().addingTimeInterval(2.0)
        while !(demuxLoopPaused && videoLoopPaused && audioLoopPaused) && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        // 5. Close the old demuxer and install the new one
        let oldDemuxer = demuxer
        demuxer = newDemuxer
        oldDemuxer.close()

        // 6. Reset queues so dequeue/enqueue work again
        videoQueue.reset()
        audioQueue.reset()

        // 7. Flush the decoders' internal state (avcodec_flush_buffers)
        _ = videoDecoder?.flush()
        _ = audioDecoder?.flush()

        // 8. Flush audio output (captures sample-time baseline) and restart at 0.
        //    The new stream is 0-based PTS so audio clock starts at 0.
        audioOutput.flush()
        audioOutput.restartAfterFlush(startPTS: 0)
        if pauseAfter {
            audioOutput.pause()
        }

        // 9. Reset state flags
        isEOF = false
        forceDisplayNextFrame = true

        // 10. Resume loops
        isSeeking = false

        #if DEBUG
        print("[BufferCoordinator] Replace complete")
        #endif
    }

    // MARK: - Demux Loop

    private func demuxLoop() {
        while isRunning {
            if isSeeking {
                demuxLoopPaused = true
                while isSeeking && isRunning {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                demuxLoopPaused = false
                if !isRunning { return }
            }

            // demuxer reference may have been swapped during seek — read fresh each iter
            let dmx = demuxer
            guard let packet = dmx.readPacket() else {
                if isSeeking { continue } // Don't EOF during a seek
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

    // MARK: - Audio Decode Loop

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
            if isSeeking {
                audioLoopPaused = true
                while isSeeking && isRunning {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                audioLoopPaused = false
                if !isRunning { break }
            }

            // Don't accumulate buffers while audio output is paused
            while audioOutput.isPaused && !isSeeking && isRunning {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if isSeeking { continue }
            if !isRunning { break }

            guard let packet = audioQueue.dequeue(timeout: 0.05) else {
                if isEOF && audioQueue.isEmpty {
                    #if DEBUG
                    print("[Audio Loop] EOF, decoded \(audioFrameCount) frames")
                    #endif
                    return
                }
                continue
            }
            // Re-check after dequeue: a seek may have started while we were waiting
            if isSeeking { continue }
            guard let avPkt = packet.avPacket else { continue }
            let frames = decoder.decode(packet: avPkt)
            // Re-check after decoding (it can take time): drop stale frames
            if isSeeking { continue }
            for frame in frames {
                if isSeeking { break }
                audioOutput.scheduleBuffer(frame.pcmBuffer)
                audioFrameCount += 1
            }
            #if DEBUG
            if audioFrameCount > 0 && audioFrameCount % 200 == 0 {
                print("[Audio Loop] Decoded \(audioFrameCount), queue: \(audioQueue.count)")
            }
            #endif
        }
        #if DEBUG
        print("[Audio Loop] Stopped, decoded \(audioFrameCount) frames")
        #endif
    }

    // MARK: - Video Decode Loop

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
            if isSeeking {
                videoLoopPaused = true
                while isSeeking && isRunning {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                videoLoopPaused = false
                if !isRunning { break }
            }

            // While paused, only proceed if we need to force-display next frame
            while syncClock.isPaused && !forceDisplayNextFrame && !isSeeking && isRunning {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if isSeeking { continue }
            if !isRunning { break }

            guard let packet = videoQueue.dequeue(timeout: 0.05) else {
                if isEOF && videoQueue.isEmpty {
                    #if DEBUG
                    print("[Video Loop] EOF, decoded \(videoFrameCount) frames")
                    #endif
                    return
                }
                continue
            }
            // Re-check after dequeue: a seek may have started while we were waiting
            if isSeeking { continue }
            guard let avPkt = packet.avPacket else { continue }
            let frames = decoder.decode(packet: avPkt)
            // Re-check after decoding (it can take time): drop stale frames
            if isSeeking { continue }
            for frame in frames {
                if isSeeking { break }
                displayWithSync(frame)
                videoFrameCount += 1
            }
            #if DEBUG
            if videoFrameCount > 0 && videoFrameCount % 100 == 0 {
                print("[Video Loop] Decoded \(videoFrameCount), queue: \(videoQueue.count), clock: \(String(format: "%.1f", syncClock.currentTime))s")
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

        while isRunning && !isSeeking {
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
