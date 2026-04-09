import Foundation
#if !targetEnvironment(simulator)
import CFFmpeg
#endif

enum PacketStreamType {
    case video
    case audio
    case subtitle
}

/// Wrapper around FFmpeg AVPacket.
/// Owns a cloned copy via av_packet_clone. The ref-counted buffer
/// stays alive until this object is deallocated.
nonisolated final class DemuxedPacket: @unchecked Sendable {
    // Store as raw Int to avoid Swift 6 deinit isolation issues
    nonisolated(unsafe) private let pktAddress: Int

    let streamType: PacketStreamType
    let streamIndex: Int32
    let ptsSeconds: Double
    let durationSeconds: Double

    #if !targetEnvironment(simulator)
    /// Access the AVPacket pointer (valid for lifetime of this object)
    var avPacket: UnsafeMutablePointer<AVPacket>? {
        UnsafeMutablePointer(bitPattern: pktAddress)
    }

    init(packet: UnsafeMutablePointer<AVPacket>, streamType: PacketStreamType, streamIndex: Int32, pts: Double, duration: Double) {
        if let cloned = av_packet_clone(packet) {
            self.pktAddress = Int(bitPattern: cloned)
        } else {
            self.pktAddress = 0
        }
        self.streamType = streamType
        self.streamIndex = streamIndex
        self.ptsSeconds = pts
        self.durationSeconds = duration
    }

    deinit {
        if let ptr = UnsafeMutablePointer<AVPacket>(bitPattern: pktAddress) {
            var p: UnsafeMutablePointer<AVPacket>? = ptr
            av_packet_free(&p)
        }
    }
    #else
    init(streamType: PacketStreamType, streamIndex: Int32, pts: Double, duration: Double) {
        self.pktAddress = 0
        self.streamType = streamType
        self.streamIndex = streamIndex
        self.ptsSeconds = pts
        self.durationSeconds = duration
    }
    #endif
}
