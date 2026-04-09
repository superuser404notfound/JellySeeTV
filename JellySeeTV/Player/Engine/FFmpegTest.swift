import Foundation
import CFFmpeg

/// Quick test to verify FFmpeg is linked correctly
enum FFmpegTest {
    static func verify() {
        let version = avformat_version()
        let major = version >> 16
        let minor = (version >> 8) & 0xFF
        let micro = version & 0xFF
        print("[FFmpeg] libavformat version: \(major).\(minor).\(micro)")

        let codecVersion = avcodec_version()
        let cmajor = codecVersion >> 16
        let cminor = (codecVersion >> 8) & 0xFF
        let cmicro = codecVersion & 0xFF
        print("[FFmpeg] libavcodec version: \(cmajor).\(cminor).\(cmicro)")
    }
}
