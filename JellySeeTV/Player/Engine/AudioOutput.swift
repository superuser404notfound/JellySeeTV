import AVFoundation

/// Audio output via AVAudioEngine. Also serves as the master clock for A/V sync.
final class AudioOutput {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var startPTS: Double = 0
    private var isStarted = false

    /// Samples scheduled but not yet played (for clock calculation)
    private var scheduledSamples: Int64 = 0

    init() {
        engine.attach(playerNode)
    }

    // MARK: - Start / Stop

    func start(format: AVAudioFormat, startPTS: Double = 0) throws {
        self.format = format
        self.startPTS = startPTS
        self.scheduledSamples = 0

        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try engine.start()
        playerNode.play()
        isStarted = true

        #if DEBUG
        print("[AudioOutput] Started: \(format.sampleRate)Hz, \(format.channelCount)ch")
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

    /// Schedule a PCM buffer for playback
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer)
        scheduledSamples += Int64(buffer.frameLength)
    }

    // MARK: - Master Clock

    /// Current playback time in seconds. This is THE master clock for A/V sync.
    var currentPlaybackTime: Double {
        guard isStarted, let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return startPTS
        }

        let sampleTime = Double(playerTime.sampleTime) / playerTime.sampleRate
        return startPTS + sampleTime
    }

    // MARK: - Flush (for seeking)

    func flush() {
        playerNode.stop()
        playerNode.reset()
        scheduledSamples = 0
    }

    func restartAfterFlush(startPTS: Double) {
        self.startPTS = startPTS
        playerNode.play()
    }
}
