import AVFoundation

/// Audio output via AVAudioEngine. Decodes all audio to PCM for playback.
/// Serves as the master clock for A/V sync.
///
/// Designed to be reused across seeks: flush() captures a sample-time baseline,
/// so the clock returns the new startPTS immediately after restart.
nonisolated final class AudioOutput {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var startPTS: Double = 0
    private var isStarted = false
    private var scheduledSamples: Int64 = 0
    private var lastKnownTime: Double = 0
    /// AVAudioPlayerNode.sampleTime is monotonic across stop/play, so we
    /// capture the value at flush() and subtract it in currentPlaybackTime.
    /// This makes the clock "reset" relative to the new playback start.
    private var sampleTimeBase: AVAudioFramePosition = 0

    init() {
        engine.attach(playerNode)
    }

    // MARK: - Start / Stop

    func start(format: AVAudioFormat, startPTS: Double = 0) throws {
        self.format = format
        self.startPTS = startPTS
        self.scheduledSamples = 0
        self.lastKnownTime = startPTS
        self.sampleTimeBase = 0

        // Configure audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            #if DEBUG
            print("[AudioOutput] Audio session configured")
            #endif
        } catch {
            #if DEBUG
            print("[AudioOutput] Audio session error: \(error)")
            #endif
            throw error
        }

        // Connect and start engine
        do {
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            try engine.start()
            #if DEBUG
            print("[AudioOutput] Engine started, running: \(engine.isRunning)")
            #endif
        } catch {
            #if DEBUG
            print("[AudioOutput] Engine start error: \(error)")
            #endif
            throw error
        }

        playerNode.play()
        isStarted = true

        #if DEBUG
        print("[AudioOutput] Playing: \(format.sampleRate)Hz, \(format.channelCount)ch")
        #endif
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isStarted = false
        scheduledSamples = 0
    }

    func pause() {
        playerNode.pause()
    }

    func resume() {
        playerNode.play()
    }

    var isPaused: Bool {
        !playerNode.isPlaying
    }

    // MARK: - Schedule Audio

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer)
        scheduledSamples += Int64(buffer.frameLength)
    }

    // MARK: - Master Clock

    /// Current playback time in seconds. THE master clock for A/V sync.
    var currentPlaybackTime: Double {
        guard isStarted else { return lastKnownTime }
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return lastKnownTime
        }
        // Subtract the baseline captured at the last flush() — makes the
        // sample counter "reset" to 0 across seeks while keeping the same
        // underlying playerNode (avoiding VT/audio-engine resource churn).
        let relativeSamples = max(0, playerTime.sampleTime - sampleTimeBase)
        let rawTime = startPTS + Double(relativeSamples) / playerTime.sampleRate
        let latency = AVAudioSession.sharedInstance().outputLatency
        let time = max(startPTS, rawTime - latency)
        lastKnownTime = time
        return time
    }

    // MARK: - Flush (for seeking)

    /// Flush all scheduled buffers and capture a new sample-time baseline.
    /// After this, currentPlaybackTime will return startPTS until new buffers play.
    func flush() {
        // Capture current sampleTime BEFORE stopping (after stop, lastRenderTime
        // becomes nil). This becomes the new "zero" for currentPlaybackTime.
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            // Add scheduled samples that haven't played yet, so any in-flight
            // audio is fully accounted for as the baseline.
            sampleTimeBase = playerTime.sampleTime + AVAudioFramePosition(scheduledSamples)
        }
        playerNode.stop()
        playerNode.reset()
        scheduledSamples = 0
    }

    func restartAfterFlush(startPTS: Double) {
        self.startPTS = startPTS
        self.lastKnownTime = startPTS
        playerNode.play()
    }
}
