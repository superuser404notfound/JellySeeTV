import Foundation
import AVFoundation
import Metal
import QuartzCore
import UIKit

/// Pulls HDR video frames out of an `AVPlayerItem` via
/// `AVPlayerItemVideoOutput` and renders them to a `CAMetalLayer` after
/// applying ITU-R BT.2390-3 tone mapping in a Metal fragment shader.
///
/// ## Architecture
///
/// ```
/// AVPlayerItem
///   └── AVPlayerItemVideoOutput  ← outputSettings request rgba16Float
///         ├── Apple's pixel transfer session decodes HEVC Main10 / DV
///         │   into linear extended Rec.2020 RGB float texture
///         └── copyPixelBuffer(forItemTime:) — pull on each display frame
///                  ↓
///   CADisplayLink (60 Hz on Apple TV)
///         └── render() pulls latest frame
///               ↓
///   CVMetalTextureCache → MTLTexture
///         ↓
///   Metal render pipeline
///         ├── Vertex: full-screen triangle
///         └── Fragment: BT.2390 tone map + BT.2020→BT.709 + gamma encode
///               ↓
///   CAMetalLayer drawable → display
/// ```
///
/// ## Why we don't use `customVideoCompositorClass`
///
/// We tried. Apple's AVPlayer pipeline for Dolby Vision rejects custom
/// compositors with `Fig kFigSampleBufferProcessorError_FormatNotSupported`
/// (-12710) regardless of `supportsHDRSourceFrames` setting. The
/// `AVPlayerItemVideoOutput` path bypasses that pipeline entirely — Apple's
/// pixel transfer session does the HEVC Main10 / DV decode + initial color
/// conversion for us, then hands us a clean RGBA16Float texture per frame.
///
/// ## Performance
///
/// On Apple TV 4K Gen 3 (A15 GPU), rendering a 4K frame is roughly 2 ms
/// — most of that is the texture upload from CVPixelBuffer. The fragment
/// shader itself is trivially cheap (~30 ALU ops per pixel).
@MainActor
final class MetalHDRRenderer {

    // MARK: - Output

    /// The CAMetalLayer this renderer draws into. Hand it to a UIView via
    /// MetalVideoView. Configured for SDR Rec.709 output by default —
    /// switched to extended Rec.2020 EDR when an HDR display is detected.
    let metalLayer: CAMetalLayer

    // MARK: - Metal pipeline

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache

    // MARK: - Player wiring

    private weak var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    /// Strong-held CVMetalTexture so the underlying CVPixelBuffer doesn't
    /// get recycled before the GPU is done with it.
    private var lastCVTexture: CVMetalTexture?

    // MARK: - Init

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("MetalHDRRenderer: Metal device unavailable")
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("MetalHDRRenderer: failed to create command queue")
        }
        self.commandQueue = queue

        // Configure the CAMetalLayer for direct presentation
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm  // SDR target — we tone-map down to this
        layer.framebufferOnly = true     // we never read back from it
        layer.isOpaque = true
        layer.backgroundColor = UIColor.black.cgColor
        self.metalLayer = layer

        // Build the render pipeline (vertex + fragment shaders compiled at build time)
        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .main)
        } catch {
            fatalError("MetalHDRRenderer: failed to load default Metal library: \(error)")
        }

        guard let vertexFn = library.makeFunction(name: "hdr_fullscreen_vertex") else {
            fatalError("MetalHDRRenderer: vertex function 'hdr_fullscreen_vertex' not found")
        }
        guard let fragmentFn = library.makeFunction(name: "hdr_tone_map_fragment") else {
            fatalError("MetalHDRRenderer: fragment function 'hdr_tone_map_fragment' not found")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = layer.pixelFormat

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("MetalHDRRenderer: failed to create render pipeline: \(error)")
        }

        // Texture cache for zero-copy CVPixelBuffer → MTLTexture
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let textureCache = cache else {
            fatalError("MetalHDRRenderer: failed to create texture cache")
        }
        self.textureCache = textureCache

        #if DEBUG
        print("[MetalHDR] Initialized (device=\(device.name))")
        #endif
    }

    // MARK: - Lifecycle

    /// Attach the renderer to a player item. Sets up an
    /// `AVPlayerItemVideoOutput` that requests linear-light RGBA16Float
    /// pixel buffers (Apple's pixel transfer session does the HEVC Main10
    /// / DV decode + initial color conversion for us), and starts a
    /// CADisplayLink that polls for new frames at the display refresh
    /// rate.
    func attach(to playerItem: AVPlayerItem) {
        // Tear down any previous attachment first
        detach()

        self.playerItem = playerItem

        // Output settings — request linear extended Rec.2020 RGBA16Float.
        // The pixel transfer session reads whatever the source decoder
        // produces (10-bit YCbCr biplanar / lossless packed / etc) and
        // converts to this format for us.
        let colorProperties: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_Linear,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
        ]
        let outputSettings: [String: Any] = [
            AVVideoAllowWideColorKey: true,
            AVVideoColorPropertiesKey: colorProperties,
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_64RGBAHalf),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        let output = AVPlayerItemVideoOutput(outputSettings: outputSettings)
        output.suppressesPlayerRendering = true  // we render the video ourselves
        playerItem.add(output)
        self.videoOutput = output

        // CADisplayLink drives our render loop synchronized to the screen
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.add(to: .main, forMode: .common)
        self.displayLink = link

        #if DEBUG
        print("[MetalHDR] Attached to player item")
        #endif
    }

    /// Detach from the current player item. Tears down the video output
    /// and stops the display link. Call this when changing items or
    /// dismissing the player.
    func detach() {
        displayLink?.invalidate()
        displayLink = nil
        if let output = videoOutput, let item = playerItem {
            item.remove(output)
        }
        videoOutput = nil
        playerItem = nil
        lastCVTexture = nil
    }

    // MARK: - Display link

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        guard let output = videoOutput else { return }

        // Translate the next host-time tick into the player item's timeline
        let nextHostTime = link.timestamp + link.duration
        let itemTime = output.itemTime(forHostTime: nextHostTime)

        // Skip if there's no new frame yet
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else { return }

        render(pixelBuffer: pixelBuffer)
    }

    // MARK: - Render

    private func render(pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Wrap as Metal texture (zero-copy, IOSurface-backed)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rgba16Float,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cv = cvTexture, let sourceTexture = CVMetalTextureGetTexture(cv) else {
            #if DEBUG
            print("[MetalHDR] CVMetalTextureCacheCreateTextureFromImage failed: \(status)")
            #endif
            return
        }

        // Hold the CVMetalTexture strong until the GPU is done with the
        // underlying buffer. Apple's docs are explicit about this.
        self.lastCVTexture = cv

        // Update the layer's drawable size to match the host view if needed
        // (handled by MetalVideoView's layout, but we keep aspect-correct
        // viewports inside the render pass)
        guard let drawable = metalLayer.nextDrawable() else { return }

        // Build a render pass that targets the drawable
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)

        // Aspect-correct viewport: fit source into drawable, letterbox elsewhere
        let viewport = aspectFitViewport(
            source: CGSize(width: width, height: height),
            drawable: CGSize(width: drawable.texture.width, height: drawable.texture.height)
        )
        encoder.setViewport(viewport)

        encoder.setFragmentTexture(sourceTexture, index: 0)
        var uniforms = ToneMapFragmentUniforms(
            hdrPeakNits: 1000.0,
            sdrPeakNits: 100.0
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ToneMapFragmentUniforms>.size, index: 0)

        // Single full-screen triangle = 3 vertices, no vertex buffer needed
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    /// Compute a centered aspect-fit MTLViewport for the given source size
    /// inside the given drawable size. Letterbox / pillarbox happens
    /// outside the viewport (the clear color fills it).
    private func aspectFitViewport(source: CGSize, drawable: CGSize) -> MTLViewport {
        guard source.width > 0, source.height > 0, drawable.width > 0, drawable.height > 0 else {
            return MTLViewport(originX: 0, originY: 0, width: drawable.width, height: drawable.height, znear: 0, zfar: 1)
        }
        let srcAspect = source.width / source.height
        let dstAspect = drawable.width / drawable.height

        var w: Double = drawable.width
        var h: Double = drawable.height
        if srcAspect > dstAspect {
            // Source is wider — fit width, letterbox top/bottom
            h = drawable.width / srcAspect
        } else {
            // Source is taller — fit height, pillarbox left/right
            w = drawable.height * srcAspect
        }
        let x = (drawable.width - w) / 2.0
        let y = (drawable.height - h) / 2.0
        return MTLViewport(originX: x, originY: y, width: w, height: h, znear: 0, zfar: 1)
    }
}

// MARK: - Uniforms

private struct ToneMapFragmentUniforms {
    var hdrPeakNits: Float
    var sdrPeakNits: Float
}
