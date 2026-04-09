import AVFoundation
import CoreMedia
import CoreVideo

/// Renders decoded CVPixelBuffer frames via AVSampleBufferDisplayLayer.
final class VideoRenderer {
    let displayLayer = AVSampleBufferDisplayLayer()

    init() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
    }

    /// Enqueue a decoded video frame for display
    func enqueue(pixelBuffer: CVPixelBuffer, pts: Double, duration: Double) {
        // Create CMSampleBuffer from CVPixelBuffer
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let desc = formatDescription else { return }

        // Timing info
        let ptsTime = CMTime(seconds: pts, preferredTimescale: 90000)
        let durTime = CMTime(seconds: duration, preferredTimescale: 90000)
        var timingInfo = CMSampleTimingInfo(
            duration: durTime,
            presentationTimeStamp: ptsTime,
            decodeTimeStamp: .invalid
        )

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sb = sampleBuffer else { return }

        // Mark as display-immediately for our custom sync
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as? [NSMutableDictionary],
           let dict = attachments.first {
            dict[kCMSampleAttachmentKey_DisplayImmediately] = true
        }

        // Enqueue for display
        if displayLayer.isReadyForMoreMediaData {
            displayLayer.enqueue(sb)
        }
    }

    /// Flush the display layer (on seek)
    func flush() {
        displayLayer.flush()
    }

    /// Request time control for smooth playback
    func requestMediaDataWhenReady(on queue: DispatchQueue, using block: @escaping () -> Void) {
        displayLayer.requestMediaDataWhenReady(on: queue, using: block)
    }
}
