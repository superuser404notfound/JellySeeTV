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
    /// Range off). Forces the server to:
    /// - tone-map HDR → SDR (via Jellyfin's tone-mapping pipeline)
    /// - downscale 4K → 1080p
    /// - re-encode to H.264 (NOT HEVC — H.264 encoding is 5–10x
    ///   faster, the difference between real-time and the encoder
    ///   falling behind)
    /// - downmix multi-channel audio to stereo AC3
    static func conservativeSDRProfile() -> [String: Any] {
        [
            // Bitrate cap: realistic for 1080p H.264, gives the encoder
            // headroom but doesn't ask for impossible throughput.
            "MaxStreamingBitrate": 25_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,

            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,alac,flac,opus,mp3",
                ],
                [
                    "Container": "mp3,aac,m4a,m4b,flac,alac,wav,opus",
                    "Type": "Audio",
                ],
            ] as [[String: Any]],

            // H.264 only as the transcode target — much faster than HEVC
            // to encode in real time on a CPU without hardware encoder.
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "mp4",
                    "Protocol": "hls",
                    "VideoCodec": "h264",
                    "AudioCodec": "aac,ac3",
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

            // Force SDR + 8-bit + Main + stereo + 1080p. Anything in
            // the source that violates these triggers a real transcode.
            "CodecProfiles": [
                [
                    "Type": "Video",
                    "Codec": "hevc",
                    "Conditions": [
                        [
                            "Condition": "EqualsAny",
                            "Property": "VideoRangeType",
                            "Value": "SDR",
                            "IsRequired": true,
                        ],
                        [
                            "Condition": "EqualsAny",
                            "Property": "VideoProfile",
                            "Value": "main",
                            "IsRequired": true,
                        ],
                        [
                            "Condition": "LessThanEqual",
                            "Property": "VideoBitDepth",
                            "Value": "8",
                            "IsRequired": true,
                        ],
                    ],
                ],
                [
                    "Type": "Video",
                    "Codec": "h264",
                    "Conditions": [
                        [
                            "Condition": "EqualsAny",
                            "Property": "VideoRangeType",
                            "Value": "SDR",
                            "IsRequired": true,
                        ],
                        [
                            "Condition": "LessThanEqual",
                            "Property": "VideoBitDepth",
                            "Value": "8",
                            "IsRequired": true,
                        ],
                    ],
                ],
                [
                    "Type": "VideoAudio",
                    "Conditions": [
                        [
                            "Condition": "LessThanEqual",
                            "Property": "AudioChannels",
                            "Value": "2",
                            "IsRequired": true,
                        ],
                    ],
                ],
                [
                    "Type": "Video",
                    "Conditions": [
                        [
                            "Condition": "LessThanEqual",
                            "Property": "Width",
                            "Value": "1920",
                            "IsRequired": true,
                        ],
                        [
                            "Condition": "LessThanEqual",
                            "Property": "Height",
                            "Value": "1080",
                            "IsRequired": true,
                        ],
                    ],
                ],
            ] as [[String: Any]],

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
