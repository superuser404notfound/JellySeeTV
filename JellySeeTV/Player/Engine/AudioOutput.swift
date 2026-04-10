import AVFoundation

/// Audio output via AVAudioEngine. Decodes all audio to PCM for playback.
/// Serves as the master clock for A/V sync.
nonisolated final class AudioOutput {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var startPTS: Double = 0
    private var isStarted = false
    private var scheduledSamples: Int64 = 0
    private var lastKnownTime: Double = 0

    /// AVAudioPlayerNode.sampleTime can return a non-zero value at start
    /// (engine global counter, persisted state). We capture the FIRST observed
    /// sample time after start/flush as the baseline, so the clock effectively
    /// resets to startPTS each time.
    private var sampleTimeBaseline: AVAudioFramePosition? = nil

    init() {
        engine.attach(playerNode)
    }

    // MARK: - Start / Stop

    func start(format: AVAudioFormat, startPTS: Double = 0) throws {
        self.format = format
        self.startPTS = startPTS
        self.scheduledSamples = 0
        self.lastKnownTime = startPTS
        self.sampleTimeBaseline = nil

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
        sampleTimeBaseline = nil
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
    /// On the first call after start/flush, captures the current sampleTime
    /// as a baseline so the clock starts at startPTS regardless of the
    /// underlying playerNode's internal counter.
    var currentPlaybackTime: Double {
        guard isStarted else { return lastKnownTime }
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return lastKnownTime
        }

        // Capture baseline on first observation after start/flush
        if sampleTimeBaseline == nil {
            sampleTimeBaseline = playerTime.sampleTime
        }
        let baseline = sampleTimeBaseline ?? 0
        let relativeSamples = max(0, playerTime.sampleTime - baseline)

        let rawTime = startPTS + Double(relativeSamples) / playerTime.sampleRate
        let latency = AVAudioSession.sharedInstance().outputLatency
        let time = max(startPTS, rawTime - latency)
        lastKnownTime = time
        return time
    }

    // MARK: - Flush (for seeking)

    /// Flush all scheduled buffers and reset the sample-time baseline.
    /// After this + restartAfterFlush, currentPlaybackTime returns startPTS
    /// until new audio renders, then advances naturally.
    func flush() {
        playerNode.stop()
        playerNode.reset()
        scheduledSamples = 0
        // Reset baseline so the next observation captures the new starting point
        sampleTimeBaseline = nil
    }

    func restartAfterFlush(startPTS: Double) {
        self.startPTS = startPTS
        self.lastKnownTime = startPTS
        self.sampleTimeBaseline = nil
        playerNode.play()
    }
}
