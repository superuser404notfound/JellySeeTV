import Foundation
import AVFoundation
import CoreVideo

/// Minimal `AVVideoCompositing` implementation whose only job is to make
/// AVFoundation tone-map HDR content to SDR before it reaches us.
///
/// ## Why this exists
///
/// On Apple TV with "Match Dynamic Range" turned off (so the system stays
/// in SDR mode), AVPlayer's default render path tries to client-side
/// tone-map HDR streams via the EDR display pipeline at present time.
/// On 4K HEVC Main10 in HLS-fMP4 this hangs — AVPlayer never reaches
/// "Item ready" and the loading spinner is stuck forever.
///
/// AVFoundation has a *separate* HDR→SDR conversion path used for video
/// composition. Per WWDC20's "Edit and play back HDR video with
/// AVFoundation": when a custom compositor's `supportsHDRSourceFrames`
/// is `false` (the default), the framework will *automatically* convert
/// HDR source frames to SDR before passing them to the compositor.
///
/// We exploit that by attaching a no-op compositor to any HDR
/// AVPlayerItem: AVFoundation does the tone mapping, the compositor
/// hands the resulting SDR pixel buffer straight back to AVPlayer, and
/// the broken EDR-display path is bypassed entirely.
///
/// Trade-off: a tiny extra copy per frame. On Apple TV 4K's GPU/CPU
/// this is negligible compared to running our own Metal compute shader.
final class HDRPassthroughCompositor: NSObject, AVVideoCompositing {

    // We deliberately do NOT set supportsHDRSourceFrames here. Letting
    // it default to false is the entire point — that's the flag that
    // tells AVFoundation to tone-map HDR to SDR for us.

    /// Source frames we accept. SDR 8-bit YpCbCr is what AVFoundation
    /// will convert HDR sources to before handing them to us.
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ],
    ]

    /// Output pixel buffer format. Same as input — we don't change anything.
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ],
    ]

    private var renderContext: AVVideoCompositionRenderContext?
    private let renderQueue = DispatchQueue(label: "com.jellyseetv.hdrcompositor.render", qos: .userInteractive)

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderQueue.sync {
            self.renderContext = newRenderContext
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self = self else {
                request.finishCancelledRequest()
                return
            }
            self.handle(request)
        }
    }

    private func handle(_ request: AVAsynchronousVideoCompositionRequest) {
        // Pull the (already SDR-tone-mapped) source frame
        let trackIDs = request.sourceTrackIDs.map(\.int32Value)
        guard let firstTrackID = trackIDs.first,
              let sourceFrame = request.sourceFrame(byTrackID: firstTrackID) else {
            request.finish(with: NSError(
                domain: "HDRPassthroughCompositor",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "no source frame"]
            ))
            return
        }

        // Acquire a destination buffer from the render context
        guard let renderContext = self.renderContext,
              let destination = renderContext.newPixelBuffer() else {
            request.finish(with: NSError(
                domain: "HDRPassthroughCompositor",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "no destination buffer"]
            ))
            return
        }

        // Copy source → destination plane by plane. CVPixelBuffer YpCbCr
        // 420 is biplanar (Y plane + interleaved Cb/Cr plane).
        copyPixelBuffer(from: sourceFrame, to: destination)

        request.finish(withComposedVideoFrame: destination)
    }

    private func copyPixelBuffer(from src: CVPixelBuffer, to dst: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
            CVPixelBufferUnlockBaseAddress(dst, [])
        }

        let planeCount = CVPixelBufferGetPlaneCount(src)
        for plane in 0..<planeCount {
            guard let srcAddr = CVPixelBufferGetBaseAddressOfPlane(src, plane),
                  let dstAddr = CVPixelBufferGetBaseAddressOfPlane(dst, plane) else {
                continue
            }
            let srcStride = CVPixelBufferGetBytesPerRowOfPlane(src, plane)
            let dstStride = CVPixelBufferGetBytesPerRowOfPlane(dst, plane)
            let height = CVPixelBufferGetHeightOfPlane(src, plane)
            let copyStride = min(srcStride, dstStride)
            for row in 0..<height {
                let srcRow = srcAddr.advanced(by: row * srcStride)
                let dstRow = dstAddr.advanced(by: row * dstStride)
                memcpy(dstRow, srcRow, copyStride)
            }
        }
    }
}
