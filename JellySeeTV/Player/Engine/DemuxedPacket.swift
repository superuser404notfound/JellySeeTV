import Foundation
#if !targetEnvironment(simulator)
import CFFmpeg
#endif

enum PacketStreamType {
    case video
    case audio
    case subtitle
}

/// Wrapper around FFmpeg AVPacket data.
/// Copies the packet data to owned memory for safe cross-thread use.
nonisolated final class DemuxedPacket {
    let data: Data
    let size: Int32
    let pts: Int64
    let dts: Int64
    let duration: Int64
    let streamIndex: Int32
    let flags: Int32
    let streamType: PacketStreamType
    let ptsSeconds: Double
    let durationSeconds: Double

    #if !targetEnvironment(simulator)
    init(packet: UnsafeMutablePointer<AVPacket>, streamType: PacketStreamType, streamIndex: Int32, pts: Double, duration: Double) {
        // Copy packet data to owned memory
        if let pktData = packet.pointee.data, packet.pointee.size > 0 {
            self.data = Data(bytes: pktData, count: Int(packet.pointee.size))
        } else {
            self.data = Data()
        }
        self.size = packet.pointee.size
        self.pts = packet.pointee.pts
        self.dts = packet.pointee.dts
        self.duration = packet.pointee.duration
        self.streamIndex = streamIndex
        self.flags = packet.pointee.flags
        self.streamType = streamType
        self.ptsSeconds = pts
        self.durationSeconds = duration
    }

    /// Creates a temporary AVPacket pointing to our copied data for decoding.
    /// The caller must NOT free this packet -- the data is owned by DemuxedPacket.
    func withAVPacket<T>(_ body: (UnsafeMutablePointer<AVPacket>) -> T) -> T {
        let pkt = av_packet_alloc()!

        // Allocate a proper ref-counted buffer that FFmpeg/VideoToolbox can keep
        if data.count > 0 {
            av_new_packet(pkt, Int32(data.count))
            data.withUnsafeBytes { rawBuf in
                if let src = rawBuf.baseAddress {
                    memcpy(pkt.pointee.data, src, data.count)
                }
            }
        }
        pkt.pointee.pts = pts
        pkt.pointee.dts = dts
        pkt.pointee.duration = duration
        pkt.pointee.stream_index = streamIndex
        pkt.pointee.flags = flags

        let result = body(pkt)

        // av_packet_free properly frees the ref-counted buffer
        var p: UnsafeMutablePointer<AVPacket>? = pkt
        av_packet_free(&p)

        return result
    }
    #else
    init(streamType: PacketStreamType, streamIndex: Int32, pts: Double, duration: Double) {
        self.data = Data()
        self.size = 0
        self.pts = 0
        self.dts = 0
        self.duration = 0
        self.streamIndex = streamIndex
        self.flags = 0
        self.streamType = streamType
        self.ptsSeconds = pts
        self.durationSeconds = duration
    }
    #endif
}
