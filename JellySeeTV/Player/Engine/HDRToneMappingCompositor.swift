import Foundation
import AVFoundation
import CoreVideo
import Metal

/// Custom `AVVideoCompositing` implementation that runs HDR video frames
/// through a Metal compute shader to produce SDR output.
///
/// ## Architecture
///
/// AVPlayer's HEVC HW decoder hands us each frame as a 10-bit YCbCr 4:2:0
/// biplanar `CVPixelBuffer` (HDR10 PQ-encoded, BT.2020 primaries — and for
/// Dolby Vision sources, the HDR10 base layer with the per-frame RPU
/// metadata stripped, because `appliesPerFrameHDRDisplayMetadata = false`
/// is set on the `AVPlayerItem`).
///
/// We wrap each plane as a Metal texture via `CVMetalTextureCache`
/// (zero-copy on Apple Silicon), dispatch a compute kernel that:
///
///   1. Dequantizes 10-bit limited-range YCbCr to BT.2020 RGB (still PQ)
///   2. Applies the inverse PQ EOTF → linear-light nits
///   3. Tone-maps with ITU-R BT.2390-3 in PQ space (knee + Hermite spline)
///   4. Converts BT.2020 RGB → BT.709 RGB
///   5. Applies the BT.709 OETF (gamma encode)
///   6. Converts back to 8-bit YCbCr limited range (BT.709)
///
/// then writes the result into a destination 8-bit YCbCr 4:2:0 biplanar
/// `CVPixelBuffer` from the render context. AVPlayer's standard SDR
/// display path renders the result.
///
/// ## Why this exists
///
/// On Apple TV with "Match Dynamic Range" off, AVPlayer's default HDR
/// presentation path tries to client-side tone-map at present time via
/// the EDR display pipeline. On 4K HEVC Main10 in HLS-fMP4 (which is
/// every Jellyfin remuxed HDR file) that path **wedges** — AVPlayer
/// never reaches "Item ready", playback hangs forever on the loading
/// spinner.
///
/// `applyingCIFiltersWithHandler` + `CIToneMapHeadroom` is documented
/// for editing workflows but Apple does not promise it works for HLS
/// playback. AVFoundation's "automatically tone-map HDR for non-HDR-aware
/// compositors" path errors out with `Fig -12710` on Dolby Vision sources.
///
/// So we go the supported route: a custom compositor with
/// `supportsHDRSourceFrames = true`, processing every frame on the GPU
/// ourselves. Apple TV 4K Gen 3's A15 GPU does this in <5 ms per 4K
/// frame, well within real-time.
///
/// This compositor is **only** installed when the engine detects an HDR
/// source playing on a non-HDR display path. HDR sources on HDR-capable
/// displays go through AVPlayer's native HDR direct play (no compositor,
/// no tone mapping, no quality loss).
final class HDRToneMappingCompositor: NSObject, AVVideoCompositing {

    // MARK: - AVVideoCompositing required properties

    /// We accept 10-bit YCbCr 4:2:0 biplanar pixel buffers from AVFoundation.
    /// Both video-range and full-range variants — AVPlayer hands us
    /// whatever the source decoder produced.
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            Int(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
            Int(kCVPixelFormatType_420YpCbCr10BiPlanarFullRange),
        ],
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Sendable](),
    ]

    /// We produce 8-bit YCbCr 4:2:0 biplanar pixel buffers — what
    /// AVPlayer's SDR display path expects natively.
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        ],
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Sendable](),
    ]

    /// CRITICAL — without this, AVFoundation tries to convert HDR to
    /// SDR before handing us the frame, which fails for Dolby Vision
    /// with `kFigSampleBufferProcessorError_FormatNotSupported`.
    let supportsHDRSourceFrames = true

    /// HDR is implicitly wide-color; the framework requires both flags.
    let supportsWideColorSourceFrames = true

    // MARK: - Metal pipeline

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let inputTextureCache: CVMetalTextureCache
    private let outputTextureCache: CVMetalTextureCache

    // MARK: - State

    private var renderContext: AVVideoCompositionRenderContext?
    private let renderQueue = DispatchQueue(
        label: "com.jellyseetv.hdrcompositor",
        qos: .userInteractive
    )

    // MARK: - Init

    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("HDRToneMappingCompositor: Metal device unavailable")
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("HDRToneMappingCompositor: failed to create command queue")
        }
        self.commandQueue = queue

        // The Metal default library bundles every .metal file in the app target
        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .main)
        } catch {
            fatalError("HDRToneMappingCompositor: failed to load Metal library: \(error)")
        }

        guard let function = library.makeFunction(name: "hdr_to_sdr_tone_map") else {
            fatalError("HDRToneMappingCompositor: 'hdr_to_sdr_tone_map' kernel not found in Metal library")
        }

        do {
            self.pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("HDRToneMappingCompositor: failed to create compute pipeline: \(error)")
        }

        var inCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &inCache) == kCVReturnSuccess,
              let inputCache = inCache else {
            fatalError("HDRToneMappingCompositor: failed to create input texture cache")
        }
        self.inputTextureCache = inputCache

        var outCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &outCache) == kCVReturnSuccess,
              let outputCache = outCache else {
            fatalError("HDRToneMappingCompositor: failed to create output texture cache")
        }
        self.outputTextureCache = outputCache

        super.init()

        #if DEBUG
        print("[HDRTM] Initialized Metal pipeline (device=\(device.name))")
        #endif
    }

    // MARK: - AVVideoCompositing protocol

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
            self.process(request: request)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        // We process synchronously per request — nothing to drain.
    }

    // MARK: - Per-frame processing

    private func process(request: AVAsynchronousVideoCompositionRequest) {
        // 1. Pull source frame
        guard let trackID = request.sourceTrackIDs.first?.int32Value,
              let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
            request.finish(with: HDRToneMappingError.noSourceFrame)
            return
        }

        // 2. Pull destination buffer from the render context
        guard let context = self.renderContext,
              let destBuffer = context.newPixelBuffer() else {
            request.finish(with: HDRToneMappingError.noDestinationBuffer)
            return
        }

        // 3. Detect transfer function from the source buffer attachments.
        // Default to PQ — most HDR sources are HDR10 or DV (which has a
        // PQ base layer). HLG is the exception.
        let transferFunction: UInt32 = isHLGEncoded(sourceBuffer) ? 1 : 0

        // 4. Wrap source pixel buffer planes as Metal textures.
        // Plane 0 is luma (Y), plane 1 is chroma (CbCr interleaved at half res).
        // For 10-bit packed-into-16-bit data, .r16Unorm / .rg16Unorm are correct
        // — the upper 10 bits hold the actual sample value.
        guard let yIn = makeMetalTexture(
            from: sourceBuffer, plane: 0, format: .r16Unorm, cache: inputTextureCache
        ),
        let cbcrIn = makeMetalTexture(
            from: sourceBuffer, plane: 1, format: .rg16Unorm, cache: inputTextureCache
        ) else {
            request.finish(with: HDRToneMappingError.textureCreationFailed)
            return
        }

        // 5. Wrap destination pixel buffer planes as 8-bit Metal textures.
        guard let yOut = makeMetalTexture(
            from: destBuffer, plane: 0, format: .r8Unorm, cache: outputTextureCache
        ),
        let cbcrOut = makeMetalTexture(
            from: destBuffer, plane: 1, format: .rg8Unorm, cache: outputTextureCache
        ) else {
            request.finish(with: HDRToneMappingError.textureCreationFailed)
            return
        }

        // 6. Encode + dispatch the compute kernel
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else {
            request.finish(with: HDRToneMappingError.encoderCreationFailed)
            return
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(yIn, index: 0)
        encoder.setTexture(cbcrIn, index: 1)
        encoder.setTexture(yOut, index: 2)
        encoder.setTexture(cbcrOut, index: 3)

        var uniforms = ToneMapUniforms(
            transferFunction: transferFunction,
            hdrPeakNits: 1000.0,  // typical HDR10 mastering peak
            sdrPeakNits: 100.0    // SDR reference white
        )
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<ToneMapUniforms>.size,
            index: 0
        )

        // Dispatch over the full Y-plane resolution (1 thread per output pixel)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (yOut.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (yOut.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        // 7. Tag the destination buffer with SDR color metadata so AVPlayer's
        // display path knows what we just produced.
        CVBufferSetAttachment(
            destBuffer,
            kCVImageBufferYCbCrMatrixKey,
            kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            destBuffer,
            kCVImageBufferColorPrimariesKey,
            kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            destBuffer,
            kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_ITU_R_709_2,
            .shouldPropagate
        )

        request.finish(withComposedVideoFrame: destBuffer)
    }

    // MARK: - Helpers

    private func makeMetalTexture(
        from pixelBuffer: CVPixelBuffer,
        plane: Int,
        format: MTLPixelFormat,
        cache: CVMetalTextureCache
    ) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            format,
            width,
            height,
            plane,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cv = cvTexture else {
            #if DEBUG
            print("[HDRTM] CVMetalTextureCacheCreateTextureFromImage failed (plane=\(plane), format=\(format), status=\(status))")
            #endif
            return nil
        }
        return CVMetalTextureGetTexture(cv)
    }

    /// HLG transfer function detection. PQ is the default — anything that
    /// isn't HLG we treat as PQ-encoded.
    private func isHLGEncoded(_ buffer: CVPixelBuffer) -> Bool {
        let attachments = CVBufferCopyAttachments(buffer, .shouldPropagate) as? [CFString: Any]
        let transfer = attachments?[kCVImageBufferTransferFunctionKey] as? String
        return transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
    }
}

// MARK: - Uniforms (must match the Metal struct layout)

private struct ToneMapUniforms {
    var transferFunction: UInt32
    var hdrPeakNits: Float
    var sdrPeakNits: Float
}

// MARK: - Errors

private enum HDRToneMappingError: Error {
    case noSourceFrame
    case noDestinationBuffer
    case textureCreationFailed
    case encoderCreationFailed
}
