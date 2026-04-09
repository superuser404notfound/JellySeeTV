import Foundation
import CoreMedia
import CoreVideo
#if !targetEnvironment(simulator)
import CFFmpeg

/// Decoded video frame ready for rendering
struct DecodedVideoFrame {
    let pixelBuffer: CVPixelBuffer
    let pts: Double        // seconds
    let duration: Double   // seconds
}

/// Decodes video packets using VideoToolbox hardware acceleration (H.264/HEVC)
/// with FFmpeg software fallback for unsupported codecs.
final class VideoDecoder: @unchecked Sendable {
    private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var hwDeviceCtx: UnsafeMutablePointer<AVBufferRef>?
    private let useHardware: Bool

    /// Width and height of the decoded video
    private(set) var width: Int32 = 0
    private(set) var height: Int32 = 0

    init(codecParameters: UnsafeMutablePointer<AVCodecParameters>, useHardware: Bool = true) throws {
        self.useHardware = useHardware

        // Find decoder
        let codecID = codecParameters.pointee.codec_id
        guard let codec = avcodec_find_decoder(codecID) else {
            throw VideoDecoderError.codecNotFound
        }

        // Allocate context
        guard let ctx = avcodec_alloc_context3(codec) else {
            throw VideoDecoderError.allocationFailed
        }
        codecCtx = ctx

        // Copy parameters
        var ret = avcodec_parameters_to_context(ctx, codecParameters)
        guard ret >= 0 else {
            throw VideoDecoderError.parameterCopyFailed
        }

        // Setup VideoToolbox hardware acceleration
        if useHardware && supportsHardware(codecID: codecID) {
            ret = av_hwdevice_ctx_create(&hwDeviceCtx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, nil, nil, 0)
            if ret >= 0 {
                ctx.pointee.hw_device_ctx = av_buffer_ref(hwDeviceCtx)
                #if DEBUG
                print("[VideoDecoder] VideoToolbox hardware decode enabled")
                #endif
            } else {
                #if DEBUG
                print("[VideoDecoder] VideoToolbox init failed, using software decode")
                #endif
            }
        } else {
            #if DEBUG
            let name = String(cString: codec.pointee.name)
            print("[VideoDecoder] Software decode for codec: \(name)")
            #endif
        }

        // Set threading
        ctx.pointee.thread_count = 4
        ctx.pointee.thread_type = FF_THREAD_FRAME

        // Open codec
        ret = avcodec_open2(ctx, codec, nil)
        guard ret >= 0 else {
            throw VideoDecoderError.openFailed
        }

        width = codecParameters.pointee.width
        height = codecParameters.pointee.height
    }

    // MARK: - Decode

    /// Decode a video packet into one or more video frames
    func decode(packet: UnsafeMutablePointer<AVPacket>) -> [DecodedVideoFrame] {
        guard let ctx = codecCtx else { return [] }

        var ret = avcodec_send_packet(ctx, packet)
        guard ret >= 0 else { return [] }

        var frames: [DecodedVideoFrame] = []
        let frame = av_frame_alloc()!
        defer {
            var f: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&f)
        }

        while true {
            ret = avcodec_receive_frame(ctx, frame)
            if ret < 0 { break } // EAGAIN or error

            if let pixelBuffer = extractPixelBuffer(from: frame) {
                let pts = framePTS(frame)
                let dur = frameDuration(frame)
                frames.append(DecodedVideoFrame(pixelBuffer: pixelBuffer, pts: pts, duration: dur))
            }

            av_frame_unref(frame)
        }

        return frames
    }

    /// Flush remaining frames from the decoder (e.g., at EOF or before seek)
    func flush() -> [DecodedVideoFrame] {
        guard let ctx = codecCtx else { return [] }

        avcodec_send_packet(ctx, nil) // Send flush signal

        var frames: [DecodedVideoFrame] = []
        let frame = av_frame_alloc()!
        defer {
            var f: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&f)
        }

        while avcodec_receive_frame(ctx, frame) >= 0 {
            if let pixelBuffer = extractPixelBuffer(from: frame) {
                let pts = framePTS(frame)
                let dur = frameDuration(frame)
                frames.append(DecodedVideoFrame(pixelBuffer: pixelBuffer, pts: pts, duration: dur))
            }
            av_frame_unref(frame)
        }

        avcodec_flush_buffers(ctx)
        return frames
    }

    // MARK: - Pixel Buffer Extraction

    private func extractPixelBuffer(from frame: UnsafeMutablePointer<AVFrame>) -> CVPixelBuffer? {
        // Hardware decode: frame->data[3] is a CVPixelBuffer
        if frame.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue {
            let buffer = unsafeBitCast(frame.pointee.data.3, to: CVPixelBuffer.self)
            return buffer
        }

        // Software decode: convert AVFrame to CVPixelBuffer
        return createPixelBuffer(from: frame)
    }

    private func createPixelBuffer(from frame: UnsafeMutablePointer<AVFrame>) -> CVPixelBuffer? {
        let w = Int(frame.pointee.width)
        let h = Int(frame.pointee.height)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            w, h,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        // Copy Y plane
        if let yDest = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
            let yDestStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            let ySrcStride = Int(frame.pointee.linesize.0)
            if let ySrc = frame.pointee.data.0 {
                for row in 0..<h {
                    memcpy(yDest + row * yDestStride, ySrc + row * ySrcStride, min(yDestStride, ySrcStride))
                }
            }
        }

        // Copy UV plane (NV12)
        if let uvDest = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
            let uvDestStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
            let uvSrcStride = Int(frame.pointee.linesize.1)
            if let uvSrc = frame.pointee.data.1 {
                for row in 0..<(h / 2) {
                    memcpy(uvDest + row * uvDestStride, uvSrc + row * uvSrcStride, min(uvDestStride, uvSrcStride))
                }
            }
        }

        return pb
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

    private func frameDuration(_ frame: UnsafeMutablePointer<AVFrame>) -> Double {
        guard let ctx = codecCtx else { return 0 }
        let tb = ctx.pointee.time_base
        let dur = frame.pointee.duration
        if dur > 0 {
            return Double(dur) * av_q2d(tb)
        }
        // Estimate from framerate
        let fps = av_q2d(ctx.pointee.framerate)
        return fps > 0 ? 1.0 / fps : 1.0 / 24.0
    }

    // MARK: - Hardware Support Check

    private func supportsHardware(codecID: AVCodecID) -> Bool {
        switch codecID {
        case AV_CODEC_ID_H264, AV_CODEC_ID_HEVC:
            return true
        default:
            return false
        }
    }

    // MARK: - Cleanup

    func close() {
        if var ctx = codecCtx {
            avcodec_free_context(&ctx)
            codecCtx = nil
        }
        if var hw = hwDeviceCtx {
            av_buffer_unref(&hw)
            hwDeviceCtx = nil
        }
    }

    deinit {
        close()
    }
}

enum VideoDecoderError: LocalizedError {
    case codecNotFound
    case allocationFailed
    case parameterCopyFailed
    case openFailed

    var errorDescription: String? {
        switch self {
        case .codecNotFound: "Video codec not found"
        case .allocationFailed: "Failed to allocate decoder context"
        case .parameterCopyFailed: "Failed to copy codec parameters"
        case .openFailed: "Failed to open video decoder"
        }
    }
}

#endif // !targetEnvironment(simulator)
