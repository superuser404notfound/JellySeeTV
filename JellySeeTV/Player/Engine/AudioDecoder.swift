import Foundation
import AVFoundation
#if !targetEnvironment(simulator)
import CFFmpeg

/// Decoded audio frame ready for playback
struct DecodedAudioFrame {
    let pcmBuffer: AVAudioPCMBuffer
    let pts: Double // seconds
}

/// Decodes audio packets via FFmpeg and converts to float32 PCM for AVAudioEngine.
/// All codecs (AC3, EAC3/Atmos, DTS, TrueHD, FLAC, etc.) are decoded to
/// multi-channel PCM. Dolby Atmos spatial metadata is decoded as 5.1/7.1 surround.
final class AudioDecoder: @unchecked Sendable {
    private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var swrCtx: OpaquePointer? // SwrContext
    private var outputFormat: AVAudioFormat?

    /// The audio format for AVAudioEngine output
    private(set) var audioFormat: AVAudioFormat?

    init(codecParameters: UnsafeMutablePointer<AVCodecParameters>) throws {
        let codecID = codecParameters.pointee.codec_id
        guard let codec = avcodec_find_decoder(codecID) else {
            throw AudioDecoderError.codecNotFound
        }

        guard let ctx = avcodec_alloc_context3(codec) else {
            throw AudioDecoderError.allocationFailed
        }
        codecCtx = ctx

        var ret = avcodec_parameters_to_context(ctx, codecParameters)
        guard ret >= 0 else {
            throw AudioDecoderError.parameterCopyFailed
        }

        ctx.pointee.thread_count = 2
        ret = avcodec_open2(ctx, codec, nil)
        guard ret >= 0 else {
            throw AudioDecoderError.openFailed
        }

        // Determine output format
        let sampleRate = Double(ctx.pointee.sample_rate > 0 ? ctx.pointee.sample_rate : 48000)
        let channels = ctx.pointee.ch_layout.nb_channels > 0 ? ctx.pointee.ch_layout.nb_channels : 2

        audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channels)
        )

        // Setup swresample for format conversion → float32 planar
        try setupResampler(ctx: ctx, sampleRate: Int32(sampleRate), channels: channels)

        #if DEBUG
        let codecName = String(cString: codec.pointee.name)
        print("[AudioDecoder] Codec: \(codecName), \(sampleRate)Hz, \(channels)ch")
        #endif
    }

    // MARK: - Decode

    func decode(packet: UnsafeMutablePointer<AVPacket>) -> [DecodedAudioFrame] {
        guard let ctx = codecCtx else { return [] }

        var ret = avcodec_send_packet(ctx, packet)
        guard ret >= 0 else { return [] }

        var frames: [DecodedAudioFrame] = []
        let frame = av_frame_alloc()!
        defer {
            var f: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&f)
        }

        while true {
            ret = avcodec_receive_frame(ctx, frame)
            if ret < 0 { break }

            if let pcmBuffer = convertToPCM(frame: frame) {
                let pts = framePTS(frame)
                frames.append(DecodedAudioFrame(pcmBuffer: pcmBuffer, pts: pts))
            }

            av_frame_unref(frame)
        }

        return frames
    }

    func flush() -> [DecodedAudioFrame] {
        guard let ctx = codecCtx else { return [] }
        avcodec_send_packet(ctx, nil)

        var frames: [DecodedAudioFrame] = []
        let frame = av_frame_alloc()!
        defer {
            var f: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&f)
        }

        while avcodec_receive_frame(ctx, frame) >= 0 {
            if let pcmBuffer = convertToPCM(frame: frame) {
                let pts = framePTS(frame)
                frames.append(DecodedAudioFrame(pcmBuffer: pcmBuffer, pts: pts))
            }
            av_frame_unref(frame)
        }

        avcodec_flush_buffers(ctx)
        return frames
    }

    // MARK: - Resampler Setup

    private func setupResampler(ctx: UnsafeMutablePointer<AVCodecContext>, sampleRate: Int32, channels: Int32) throws {
        var swr = swr_alloc()
        guard swr != nil else {
            throw AudioDecoderError.resamplerFailed
        }

        // Input layout
        var inLayout = ctx.pointee.ch_layout
        var outLayout = AVChannelLayout()
        av_channel_layout_default(&outLayout, channels)

        swr_alloc_set_opts2(
            &swr,
            &outLayout,
            AV_SAMPLE_FMT_FLTP,    // output: float32 planar
            sampleRate,
            &inLayout,
            ctx.pointee.sample_fmt, // input: whatever the codec outputs
            ctx.pointee.sample_rate,
            0, nil
        )

        let ret = swr_init(swr)
        guard ret >= 0 else {
            swr_free(&swr)
            throw AudioDecoderError.resamplerFailed
        }
        swrCtx = swr
    }

    // MARK: - PCM Conversion

    private func convertToPCM(frame: UnsafeMutablePointer<AVFrame>) -> AVAudioPCMBuffer? {
        guard let swr = swrCtx, let format = audioFormat else { return nil }

        let srcSamples = Int(frame.pointee.nb_samples)
        let srcRate = Int64(frame.pointee.sample_rate)
        let dstRate = Int64(format.sampleRate)

        // Calculate output sample count
        let dstSamples = Int(av_rescale_rnd(
            Int64(srcSamples), dstRate, srcRate, AV_ROUND_UP
        ))

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(dstSamples)) else {
            return nil
        }

        // Get output pointers
        let channels = Int(format.channelCount)
        guard let floatData = pcmBuffer.floatChannelData else { return nil }

        // Build output pointer array for swr_convert
        var outPtrs = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: channels)
        for ch in 0..<channels {
            outPtrs[ch] = UnsafeMutableRawPointer(floatData[ch]).assumingMemoryBound(to: UInt8.self)
        }

        // Build input pointer array
        let inData = frame.pointee.extended_data!
        var inPtrs = [UnsafePointer<UInt8>?](repeating: nil, count: channels)
        for ch in 0..<min(channels, Int(frame.pointee.ch_layout.nb_channels)) {
            if let ptr = inData[ch] {
                inPtrs[ch] = UnsafePointer(ptr)
            }
        }

        // Convert
        let converted = outPtrs.withUnsafeMutableBufferPointer { outBuf in
            inPtrs.withUnsafeMutableBufferPointer { inBuf in
                swr_convert(
                    swr,
                    outBuf.baseAddress,
                    Int32(dstSamples),
                    inBuf.baseAddress,
                    frame.pointee.nb_samples
                )
            }
        }

        guard converted > 0 else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(converted)
        return pcmBuffer
    }

    // MARK: - Timing

    private func framePTS(_ frame: UnsafeMutablePointer<AVFrame>) -> Double {
        guard let ctx = codecCtx else { return 0 }
        let tb = ctx.pointee.time_base
        let pts = frame.pointee.best_effort_timestamp
        if pts != Int64(bitPattern: UInt64(0x8000000000000000)) {
            return Double(pts) * av_q2d(tb)
        }
        return 0
    }

    // MARK: - Cleanup

    func close() {
        var swr: OpaquePointer? = swrCtx
        if swr != nil { swr_free(&swr) }
        swrCtx = nil

        var ctx: UnsafeMutablePointer<AVCodecContext>? = codecCtx
        if ctx != nil { avcodec_free_context(&ctx) }
        codecCtx = nil
    }

    nonisolated deinit {}
}

enum AudioDecoderError: LocalizedError {
    case codecNotFound
    case allocationFailed
    case parameterCopyFailed
    case openFailed
    case resamplerFailed

    var errorDescription: String? {
        switch self {
        case .codecNotFound: "Audio codec not found"
        case .allocationFailed: "Failed to allocate audio decoder"
        case .parameterCopyFailed: "Failed to copy audio codec parameters"
        case .openFailed: "Failed to open audio decoder"
        case .resamplerFailed: "Failed to initialize audio resampler"
        }
    }
}

#endif // !targetEnvironment(simulator)
