import AVFoundation

/// Audio output via AVAudioEngine. Decodes all audio to PCM for playback.
/// Serves as the master clock for A/V sync.
///
/// Note: Dolby Atmos spatial metadata is lost during PCM decode.
/// The audio still plays correctly as 5.1/7.1 surround.
/// Atmos passthrough requires Apple's private HDMI bitstream API
/// and will be added as a future enhancement.
nonisolated final class AudioOutput {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var startPTS: Double = 0
    private var isStarted = false
    private var scheduledSamples: Int64 = 0
    /// Cache the last good clock time to return when paused/seeking
    private var lastKnownTime: Double = 0

    init() {
        engine.attach(playerNode)
    }

    // MARK: - Start / Stop

    func start(format: AVAudioFormat, startPTS: Double = 0) throws {
        self.format = format
        self.startPTS = startPTS
        self.scheduledSamples = 0
        self.lastKnownTime = startPTS

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
    /// Compensates for audio hardware output latency so video frames
    /// are displayed at the moment the corresponding audio is heard.
    var currentPlaybackTime: Double {
        guard isStarted else { return lastKnownTime }
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            // Paused / no recent render → return the last known good time
            return lastKnownTime
        }
        let rawTime = startPTS + Double(playerTime.sampleTime) / playerTime.sampleRate
        let latency = AVAudioSession.sharedInstance().outputLatency
        let time = rawTime - latency
        lastKnownTime = time
        return time
    }

    // MARK: - Flush (for seeking)

    func flush() {
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
