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
    nonisolated(unsafe) let syncClock: SyncClock

    nonisolated(unsafe) let videoQueue = PacketQueue(capacity: 200)
    nonisolated(unsafe) let audioQueue = PacketQueue(capacity: 400)

    nonisolated(unsafe) var onVideoFrame: ((DecodedVideoFrame) -> Void)?
    nonisolated(unsafe) var onEndOfFile: (() -> Void)?
    nonisolated(unsafe) var onError: ((String) -> Void)?

    nonisolated(unsafe) private var demuxTask: Task<Void, Never>?
    nonisolated(unsafe) private var videoDecodeTask: Task<Void, Never>?
    nonisolated(unsafe) private var audioDecodeTask: Task<Void, Never>?
    nonisolated(unsafe) private var isRunning = false
    nonisolated(unsafe) private var isEOF = false

    init(demuxer: Demuxer, videoDecoder: VideoDecoder?, audioDecoder: AudioDecoder?, audioOutput: AudioOutput) {
        self.demuxer = demuxer
        self.videoDecoder = videoDecoder
        self.audioDecoder = audioDecoder
        self.audioOutput = audioOutput
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
        videoQueue.flush()
        audioQueue.flush()
        demuxTask?.cancel()
        videoDecodeTask?.cancel()
        audioDecodeTask?.cancel()
        audioOutput.stop()
    }

    func pause() { audioOutput.pause() }
    func resume() { audioOutput.resume() }

    func seek(to seconds: Double) throws {
        audioOutput.flush()
        videoQueue.flush()
        audioQueue.flush()
        _ = videoDecoder?.flush()
        _ = audioDecoder?.flush()
        try demuxer.seek(to: seconds)
        videoQueue.reset()
        audioQueue.reset()
        audioOutput.restartAfterFlush(startPTS: seconds)
    }

    // MARK: - Loops (all run on background threads)

    private func demuxLoop() {
        while isRunning {
            guard let packet = demuxer.readPacket() else {
                isEOF = true
                Task { @MainActor in onEndOfFile?() }
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
            packet.withAVPacket { pkt in
                let frames = decoder.decode(packet: pkt)
                for frame in frames {
                    audioOutput.scheduleBuffer(frame.pcmBuffer)
                    audioFrameCount += 1
                }
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
            while syncClock.isPaused && isRunning {
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
            packet.withAVPacket { pkt in
                let frames = decoder.decode(packet: pkt)
                for frame in frames {
                    displayWithSync(frame)
                    videoFrameCount += 1
                }
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
        while isRunning {
            switch syncClock.shouldDisplay(framePTS: frame.pts) {
            case .display:
                Task { @MainActor in onVideoFrame?(frame) }
                return
            case .drop:
                return
            case .wait(let seconds):
                Thread.sleep(forTimeInterval: min(seconds, 0.05))
            }
        }
    }
}

#endif
