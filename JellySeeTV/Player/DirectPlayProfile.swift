import Foundation

/// Jellyfin device profile for AetherEngine on Apple TV.
///
/// AetherEngine demuxes MKV/MP4/AVI/TS natively via FFmpeg, so we can
/// direct-play far more containers than AVPlayer. This drastically
/// reduces server-side transcoding — the server only needs to re-encode
/// when the actual codec is unsupported (e.g. MPEG-2, VC-1).
///
/// Two flavors based on display capabilities (see `DisplayCapabilities`):
///
/// - `permissiveHDRProfile`: HDR-capable display. Direct-play 4K HEVC
///   Main10 HDR10 / Dolby Vision / HLG with multichannel audio.
///
/// - `conservativeSDRProfile`: SDR display. HDR content is still
///   direct-played — VideoToolbox handles the conversion.
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
    /// Dynamic Range on). AetherEngine handles HEVC Main10, HDR10,
    /// Dolby Vision (Profile 5/8.1/8.4), HLG, and multichannel audio.
    /// Server only has to remux containers — no re-encoding.
    static func permissiveHDRProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 200_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,

            // AetherEngine (FFmpeg) handles these containers natively.
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov,mkv,matroska,avi,mpegts,ts,ogg,webm,flv",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc,av1,vp9",
                    // Jellyfin reports DTS variants inconsistently — some
                    // builds use `dts`, some `dca`, some `dts-hd`. Listing
                    // every spelling we've seen stops the server from
                    // kicking DTS-HD MA into a transcode just because our
                    // profile didn't happen to use the exact string it
                    // chose this release.
                    "AudioCodec": "aac,ac3,eac3,mp3,flac,opus,vorbis,alac,truehd,mlp,dts,dca,dts-hd,dtshd,pcm_s16le,pcm_s24le,pcm_f32le",
                ],
                [
                    "Container": "mp3,aac,m4a,m4b,flac,alac,wav,opus,ogg",
                    "Type": "Audio",
                ],
            ] as [[String: Any]],

            // Fallback: progressive MP4 over HTTP (not HLS!). AetherEngine
            // uses a custom AVIO context with URLSession for HTTP streams,
            // which doesn't support HLS playlists. HTTP progressive download
            // works perfectly with our read-ahead buffer.
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "mp4",
                    "Protocol": "http",
                    "VideoCodec": "h264,hevc,av1,vp9",
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
    /// keep TranscodingProfile permissive so the server can stream-copy
    /// compatible codecs instead of re-encoding them. Server-side
    /// transcoding is the absolute last resort.
    ///
    /// HDR sources are intentionally NOT constrained here — VideoToolbox
    /// handles HDR-on-SDR conversion automatically.
    static func conservativeSDRProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 200_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,

            // AetherEngine (FFmpeg) handles these containers natively.
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov,mkv,matroska,avi,mpegts,ts,ogg,webm,flv",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc,av1,vp9",
                    // Jellyfin reports DTS variants inconsistently — some
                    // builds use `dts`, some `dca`, some `dts-hd`. Listing
                    // every spelling we've seen stops the server from
                    // kicking DTS-HD MA into a transcode just because our
                    // profile didn't happen to use the exact string it
                    // chose this release.
                    "AudioCodec": "aac,ac3,eac3,mp3,flac,opus,vorbis,alac,truehd,mlp,dts,dca,dts-hd,dtshd,pcm_s16le,pcm_s24le,pcm_f32le",
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
                    "VideoCodec": "h264,hevc,av1,vp9",
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

    /// All subtitle formats delivered externally — we fetch them as SRT
    /// via the Jellyfin subtitle API (server converts any format to SRT).
    /// This prevents Jellyfin from transcoding the entire video stream
    /// just because a subtitle codec is "unsupported".
    private static let subtitleProfiles: [[String: Any]] = [
        ["Format": "vtt", "Method": "External"],
        ["Format": "webvtt", "Method": "External"],
        ["Format": "srt", "Method": "External"],
        ["Format": "subrip", "Method": "External"],
        ["Format": "ass", "Method": "External"],
        ["Format": "ssa", "Method": "External"],
        ["Format": "pgssub", "Method": "External"],
        ["Format": "pgs", "Method": "External"],
        ["Format": "dvdsub", "Method": "External"],
        ["Format": "dvbsub", "Method": "External"],
    ]
}
