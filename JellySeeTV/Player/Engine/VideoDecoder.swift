import Foundation
import CoreMedia
import CoreVideo
#if !targetEnvironment(simulator)
import CFFmpeg

struct DecodedVideoFrame {
    let pixelBuffer: CVPixelBuffer
    let pts: Double
    let duration: Double
}

/// Decodes video packets using VideoToolbox hardware acceleration
/// with FFmpeg software fallback for unsupported codecs.
final class VideoDecoder: @unchecked Sendable {
    private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
    private(set) var width: Int32 = 0
    private(set) var height: Int32 = 0

    init(codecParameters: UnsafeMutablePointer<AVCodecParameters>) throws {
        let codecID = codecParameters.pointee.codec_id
        guard let codec = avcodec_find_decoder(codecID) else {
            throw VideoDecoderError.codecNotFound
        }

        guard let ctx = avcodec_alloc_context3(codec) else {
            throw VideoDecoderError.allocationFailed
        }
        codecCtx = ctx

        var ret = avcodec_parameters_to_context(ctx, codecParameters)
        guard ret >= 0 else { throw VideoDecoderError.parameterCopyFailed }

        // Try VideoToolbox hardware acceleration for H.264/HEVC
        if codecID == AV_CODEC_ID_H264 || codecID == AV_CODEC_ID_HEVC {
            var hwCtx: UnsafeMutablePointer<AVBufferRef>?
            ret = av_hwdevice_ctx_create(&hwCtx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, nil, nil, 0)
            if ret >= 0, hwCtx != nil {
                ctx.pointee.hw_device_ctx = av_buffer_ref(hwCtx)
                av_buffer_unref(&hwCtx)
                #if DEBUG
                print("[VideoDecoder] VideoToolbox hardware decode enabled")
                #endif
            }
        }

        ctx.pointee.thread_count = 4
        ctx.pointee.thread_type = FF_THREAD_FRAME

        ret = avcodec_open2(ctx, codec, nil)
        guard ret >= 0 else { throw VideoDecoderError.openFailed }

        width = codecParameters.pointee.width
        height = codecParameters.pointee.height
    }

    // MARK: - Decode

    func decode(packet: UnsafeMutablePointer<AVPacket>) -> [DecodedVideoFrame] {
        guard let ctx = codecCtx else { return [] }
        guard avcodec_send_packet(ctx, packet) >= 0 else { return [] }

        var frames: [DecodedVideoFrame] = []
        let frame = av_frame_alloc()!
        defer { av_frame_free_safe(frame) }

        while avcodec_receive_frame(ctx, frame) >= 0 {
            if let pb = extractPixelBuffer(from: frame) {
                frames.append(DecodedVideoFrame(
                    pixelBuffer: pb,
                    pts: framePTS(frame),
                    duration: frameDuration(frame)
                ))
            }
            av_frame_unref(frame)
        }
        return frames
    }

    func flush() -> [DecodedVideoFrame] {
        guard let ctx = codecCtx else { return [] }
        avcodec_send_packet(ctx, nil)

        var frames: [DecodedVideoFrame] = []
        let frame = av_frame_alloc()!
        defer { av_frame_free_safe(frame) }

        while avcodec_receive_frame(ctx, frame) >= 0 {
            if let pb = extractPixelBuffer(from: frame) {
                frames.append(DecodedVideoFrame(pixelBuffer: pb, pts: framePTS(frame), duration: frameDuration(frame)))
            }
            av_frame_unref(frame)
        }
        avcodec_flush_buffers(ctx)
        return frames
    }

    // MARK: - Pixel Buffer

    private func extractPixelBuffer(from frame: UnsafeMutablePointer<AVFrame>) -> CVPixelBuffer? {
        if frame.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue {
            return unsafeBitCast(frame.pointee.data.3, to: CVPixelBuffer.self)
        }
        return createSoftwarePixelBuffer(from: frame)
    }

    private func createSoftwarePixelBuffer(from frame: UnsafeMutablePointer<AVFrame>) -> CVPixelBuffer? {
        let w = Int(frame.pointee.width)
        let h = Int(frame.pointee.height)
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        // Y plane
        if let dst = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0), let src = frame.pointee.data.0 {
            let dstStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let srcStride = Int(frame.pointee.linesize.0)
            for row in 0..<h { memcpy(dst + row * dstStride, src + row * srcStride, min(dstStride, srcStride)) }
        }
        // UV plane
        if let dst = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1), let src = frame.pointee.data.1 {
            let dstStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let srcStride = Int(frame.pointee.linesize.1)
            for row in 0..<(h/2) { memcpy(dst + row * dstStride, src + row * srcStride, min(dstStride, srcStride)) }
        }
        return pixelBuffer
    }

    // MARK: - Timing

    private func framePTS(_ frame: UnsafeMutablePointer<AVFrame>) -> Double {
        guard let ctx = codecCtx else { return 0 }
        let pts = frame.pointee.best_effort_timestamp
        if pts != Int64(bitPattern: UInt64(0x8000000000000000)) {
            return Double(pts) * av_q2d(ctx.pointee.time_base)
        }
        return 0
    }

    private func frameDuration(_ frame: UnsafeMutablePointer<AVFrame>) -> Double {
        guard let ctx = codecCtx else { return 1.0 / 24.0 }
        let dur = frame.pointee.duration
        if dur > 0 { return Double(dur) * av_q2d(ctx.pointee.time_base) }
        let fps = av_q2d(ctx.pointee.framerate)
        return fps > 0 ? 1.0 / fps : 1.0 / 24.0
    }

    // MARK: - Cleanup

    func close() {
        var ctx: UnsafeMutablePointer<AVCodecContext>? = codecCtx
        if ctx != nil { avcodec_free_context(&ctx) }
        codecCtx = nil
    }

    nonisolated deinit {}
}

private func av_frame_free_safe(_ frame: UnsafeMutablePointer<AVFrame>) {
    var f: UnsafeMutablePointer<AVFrame>? = frame
    av_frame_free(&f)
}

enum VideoDecoderError: LocalizedError {
    case codecNotFound, allocationFailed, parameterCopyFailed, openFailed
    var errorDescription: String? {
        switch self {
        case .codecNotFound: "Video codec not found"
        case .allocationFailed: "Failed to allocate decoder"
        case .parameterCopyFailed: "Failed to copy codec parameters"
        case .openFailed: "Failed to open video decoder"
        }
    }
}

#endif
