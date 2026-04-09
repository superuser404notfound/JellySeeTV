import Foundation
#if !targetEnvironment(simulator)
import CFFmpeg
#endif

enum PacketStreamType {
    case video
    case audio
    case subtitle
}

/// Wrapper around an FFmpeg AVPacket with stream info.
final class DemuxedPacket {
    /// Raw pointer stored as Int for Swift 6 deinit compatibility
    private let packetAddress: Int
    let streamType: PacketStreamType
    let streamIndex: Int32
    let pts: Double
    let duration: Double

    #if !targetEnvironment(simulator)
    var packet: UnsafeMutablePointer<AVPacket> {
        UnsafeMutablePointer(bitPattern: packetAddress)!
    }

    init(packet: UnsafeMutablePointer<AVPacket>, streamType: PacketStreamType, streamIndex: Int32, pts: Double, duration: Double) {
        let cloned = av_packet_clone(packet)!
        self.packetAddress = Int(bitPattern: cloned)
        self.streamType = streamType
        self.streamIndex = streamIndex
        self.pts = pts
        self.duration = duration
    }

    deinit {
        if let ptr = UnsafeMutablePointer<AVPacket>(bitPattern: packetAddress) {
            var p: UnsafeMutablePointer<AVPacket>? = ptr
            av_packet_free(&p)
        }
    }
    #else
    init(streamType: PacketStreamType, streamIndex: Int32, pts: Double, duration: Double) {
        self.packetAddress = 0
        self.streamType = streamType
        self.streamIndex = streamIndex
        self.pts = pts
        self.duration = duration
    }
    #endif
}
