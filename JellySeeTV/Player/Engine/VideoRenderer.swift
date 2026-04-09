import UIKit
import CoreVideo

/// Renders decoded CVPixelBuffer frames by setting IOSurface directly on a CALayer.
/// Thread-safe: can be called from any thread; internally dispatches to main.
nonisolated final class VideoRenderer: @unchecked Sendable {
    let displayLayer = CALayer()

    #if DEBUG
    nonisolated(unsafe) private var frameCount = 0
    #endif

    init() {
        displayLayer.contentsGravity = .resizeAspect
        displayLayer.isOpaque = true
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    /// Display a decoded video frame. Safe to call from any thread.
    func display(pixelBuffer: CVPixelBuffer, pts: Double) {
        // Retain the CVPixelBuffer across the async boundary using Unmanaged
        let retained = Unmanaged.passRetained(pixelBuffer)
        let opaquePtr = retained.toOpaque()
        let address = Int(bitPattern: opaquePtr)

        #if DEBUG
        frameCount += 1
        let count = frameCount
        if count == 1 || count % 100 == 0 {
            print("[VideoRenderer] Display frame #\(count) pts=\(String(format: "%.2f", pts))s")
        }
        #endif

        DispatchQueue.main.async { [weak self] in
            // Recover and release the pixel buffer
            guard let ptr = UnsafeMutableRawPointer(bitPattern: address) else { return }
            let buf = Unmanaged<CVPixelBuffer>.fromOpaque(ptr).takeRetainedValue()

            guard let layer = self?.displayLayer else { return }

            // Get IOSurface and display
            guard let surface = CVPixelBufferGetIOSurface(buf) else { return }
            let ioSurface = unsafeBitCast(surface, to: IOSurface.self)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = ioSurface
            CATransaction.commit()
        }
    }

    /// Flush (clear current frame on seek). Call from main thread.
    func flush() {
        displayLayer.contents = nil
    }
}
