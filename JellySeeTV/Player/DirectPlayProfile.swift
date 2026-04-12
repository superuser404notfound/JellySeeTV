import Foundation

/// Jellyfin device profile for SteelPlayer (FFmpeg + Metal) on Apple TV.
///
/// SteelPlayer demuxes MKV/MP4/AVI/TS natively via FFmpeg, so we can
/// direct-play far more containers than AVPlayer. This drastically
/// reduces server-side transcoding — the server only needs to re-encode
/// when the actual codec is unsupported (e.g. MPEG-2, VC-1, DTS audio).
///
/// Two flavors based on display capabilities (see `DisplayCapabilities`):
///
/// - `permissiveHDRProfile`: HDR-capable display. Direct-play 4K HEVC
///   Main10 HDR / Dolby Vision with multi-channel EAC3. No re-encoding.
///
/// - `conservativeSDRProfile`: SDR display. HDR tone mapping is handled
///   client-side by the Metal shader (Phase 4), no server re-encoding.
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

            // SteelPlayer (FFmpeg) handles these containers natively.
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov,mkv,matroska,avi,mpegts,ts,ogg,webm,flv",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc,vp8,vp9,av1",
                    "AudioCodec": "aac,ac3,eac3,mp3,flac,opus,vorbis,alac,truehd,dca,pcm_s16le,pcm_s24le,pcm_f32le",
                ],
                [
                    "Container": "mp3,aac,m4a,m4b,flac,alac,wav,opus,ogg",
                    "Type": "Audio",
                ],
            ] as [[String: Any]],

            // Fallback: progressive MP4 over HTTP (not HLS!). SteelPlayer
            // uses a custom AVIO context with URLSession for HTTP streams,
            // which doesn't support HLS playlists. HTTP progressive download
            // works perfectly with our read-ahead buffer.
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "mp4",
                    "Protocol": "http",
                    "VideoCodec": "h264,hevc,vp8,vp9,av1",
                    "AudioCodec": "aac,ac3,eac3",
                    "Context": "Streaming",
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

            // SteelPlayer (FFmpeg) handles these containers natively.
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov,mkv,matroska,avi,mpegts,ts,ogg,webm,flv",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc,vp8,vp9,av1",
                    "AudioCodec": "aac,ac3,eac3,mp3,flac,opus,vorbis,alac,truehd,dca,pcm_s16le,pcm_s24le,pcm_f32le",
                ],
                [
                    "Container": "mp3,aac,m4a,m4b,flac,alac,wav,opus,ogg",
                    "Type": "Audio",
                ],
            ] as [[String: Any]],

            // Fallback: progressive MP4 over HTTP (not HLS!).
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "mp4",
                    "Protocol": "http",
                    "VideoCodec": "h264,hevc,vp8,vp9,av1",
                    "AudioCodec": "aac,ac3,eac3",
                    "Context": "Streaming",
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
