import Foundation

/// Jellyfin device profile for AVPlayer (AVFoundation) on Apple TV.
///
/// We have two flavors and pick one at runtime based on the connected
/// display's actual capabilities (see `DisplayCapabilities`):
///
/// - `permissiveHDRProfile`: HDR-capable display with Match Dynamic
///   Range on. AVPlayer can direct-stream 4K HEVC Main10 HDR / Dolby
///   Vision content with multi-channel EAC3 audio. The server only
///   ever has to remux containers (MKV → fMP4), no re-encoding.
///
/// - `conservativeSDRProfile`: SDR display, or HDR display with Match
///   Dynamic Range off (Apple TV stays in SDR mode). The server has
///   to tone-map HDR → SDR, downscale 4K → 1080p, and re-encode to
///   H.264 (much faster to encode than HEVC, makes the difference
///   between "real-time" and "infinite buffering").
@MainActor
enum DirectPlayProfile {

    /// Picks the right profile based on the runtime display capabilities.
    static func current() -> [String: Any] {
        let useHDR = DisplayCapabilities.supportsHDR
        #if DEBUG
        print("[Profile] Display: \(DisplayCapabilities.summary) → using \(useHDR ? "HDR" : "SDR") profile")
        #endif
        return useHDR ? permissiveHDRProfile() : conservativeSDRProfile()
    }

    // MARK: - HDR-capable display

    /// Profile for HDR-capable Apple TV setups (HDR display + Match
    /// Dynamic Range on). Permissive: AVPlayer handles HEVC Main10,
    /// HDR10, Dolby Vision, EAC3 multi-channel natively. Server only
    /// has to remux containers — no re-encoding, no tone-mapping.
    static func permissiveHDRProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 200_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,

            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,eac3,alac,flac,opus,mp3",
                ],
                [
                    "Container": "mp3,aac,m4a,m4b,flac,alac,wav,opus",
                    "Type": "Audio",
                ],
            ] as [[String: Any]],

            // For non-direct-play sources (mostly MKV), Jellyfin will
            // remux to fMP4 over HTTP. Stream copy, no re-encoding.
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "mp4",
                    "Protocol": "hls",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,eac3",
                    "Context": "Streaming",
                    "MinSegments": 1,
                    "BreakOnNonKeyFrames": true,
                ],
                [
                    "Type": "Audio",
                    "Container": "mp3",
                    "Protocol": "http",
                    "AudioCodec": "mp3",
                    "Context": "Streaming",
                ],
            ] as [[String: Any]],

            "ContainerProfiles": [] as [Any],
            "CodecProfiles": [] as [[String: Any]],
            "SubtitleProfiles": Self.subtitleProfiles,
        ]
    }

    // MARK: - SDR display fallback

    /// Profile for SDR displays (or HDR displays with Match Dynamic
    /// Range off).
    ///
    /// Strategy: maximise direct play and container-remux (DirectStream),
    /// keep TranscodingProfile permissive (h264,hevc + ac3,eac3) so the
    /// server can stream-copy compatible codecs in HLS instead of
    /// re-encoding them. Server-side transcoding is the absolute last
    /// resort and is only triggered when the source is genuinely
    /// incompatible (DTS/TrueHD audio, MPEG-2/VC-1 video, etc).
    ///
    /// HDR sources are intentionally NOT constrained here. The plan for
    /// HDR-on-SDR is the custom Metal video compositor (Strategy C in
    /// the design notes), which client-side tone-maps in a Metal compute
    /// shader without any server load.
    static func conservativeSDRProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 200_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,

            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,eac3,alac,flac,opus,mp3",
                ],
                [
                    "Container": "mp3,aac,m4a,m4b,flac,alac,wav,opus",
                    "Type": "Audio",
                ],
            ] as [[String: Any]],

            // h264,hevc + ac3,eac3 → Jellyfin can stream-copy almost
            // every source we care about, only the container changes.
            // No re-encoding, no server CPU load.
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "mp4",
                    "Protocol": "hls",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,eac3",
                    "Context": "Streaming",
                    "MinSegments": 1,
                    "BreakOnNonKeyFrames": true,
                ],
                [
                    "Type": "Audio",
                    "Container": "mp3",
                    "Protocol": "http",
                    "AudioCodec": "mp3",
                    "Context": "Streaming",
                ],
            ] as [[String: Any]],

            "ContainerProfiles": [] as [Any],
            // No codec constraints in this profile. We deliberately do
            // NOT ask the server to tone-map HDR→SDR or downscale 4K —
            // both of those force a full re-encode that the server can't
            // do in real time without hardware acceleration. HDR sources
            // will be handled by the custom Metal compositor instead.
            "CodecProfiles": [] as [[String: Any]],
            "SubtitleProfiles": Self.subtitleProfiles,
        ]
    }

    // MARK: - Subtitles (shared)

    private static let subtitleProfiles: [[String: Any]] = [
        ["Format": "vtt", "Method": "External"],
        ["Format": "webvtt", "Method": "External"],
        ["Format": "srt", "Method": "External"],
        ["Format": "subrip", "Method": "External"],
        ["Format": "ass", "Method": "Encode"],
        ["Format": "ssa", "Method": "Encode"],
        ["Format": "pgssub", "Method": "Encode"],
        ["Format": "pgs", "Method": "Encode"],
        ["Format": "dvdsub", "Method": "Encode"],
        ["Format": "dvbsub", "Method": "Encode"],
    ]
}
