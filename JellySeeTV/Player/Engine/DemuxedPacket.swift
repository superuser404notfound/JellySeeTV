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
/// Owns a cloned copy of the packet data via av_packet_clone.
/// The packet stays alive until this object is deallocated.
nonisolated final class DemuxedPacket: @unchecked Sendable {
    /// The cloned AVPacket -- ref-counted by FFmpeg, stays valid until free
    #if !targetEnvironment(simulator)
    let avPacket: UnsafeMutablePointer<AVPacket>
    #endif

    let streamType: PacketStreamType
    let streamIndex: Int32
    let ptsSeconds: Double
    let durationSeconds: Double

    #if !targetEnvironment(simulator)
    init(packet: UnsafeMutablePointer<AVPacket>, streamType: PacketStreamType, streamIndex: Int32, pts: Double, duration: Double) {
        // av_packet_clone creates a new packet with ref-counted data
        // The data buffer stays alive until av_packet_free
        self.avPacket = av_packet_clone(packet)!
        self.streamType = streamType
        self.streamIndex = streamIndex
        self.ptsSeconds = pts
        self.durationSeconds = duration
    }

    deinit {
        // Safe to free: if VideoToolbox still has a ref, it added its own
        var pkt: UnsafeMutablePointer<AVPacket>? = avPacket
        av_packet_free(&pkt)
    }
    #else
    init(streamType: PacketStreamType, streamIndex: Int32, pts: Double, duration: Double) {
        self.streamType = streamType
        self.streamIndex = streamIndex
        self.ptsSeconds = pts
        self.durationSeconds = duration
    }
    #endif
}
