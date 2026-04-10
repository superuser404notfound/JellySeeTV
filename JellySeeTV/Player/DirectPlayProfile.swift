import Foundation

/// Jellyfin device profile for AVPlayer (AVFoundation) on Apple TV.
///
/// Strategy: list exactly what AVPlayer can handle natively. Anything
/// else falls into Jellyfin's transcoding profile, which targets the
/// same AVPlayer-supported codecs and a fragmented MP4 / HLS container.
///
/// Container handling:
/// - mp4 / m4v / mov: direct play (AVPlayer's native format)
/// - mkv: AVPlayer cannot demux MKV. Jellyfin remuxes to fragmented
///   MP4 / HLS *without re-encoding* — only the container is swapped,
///   the video and audio streams are byte-for-byte the same. Cost on
///   the server is negligible (~1% CPU per stream).
/// - everything else: server-side transcode to HEVC + EAC3 in fMP4/HLS
///
/// Codec notes:
/// - AV1: NO Apple TV (as of tvOS 26 / 2026) has hardware AV1 decode.
///   AV1 is always transcoded to HEVC server-side.
/// - DTS / DTS-HD / TrueHD: AVPlayer can't decode these — transcoded
///   to EAC3 (Atmos-capable) or AC3 server-side.
/// - HEVC 10-bit / HDR10 / Dolby Vision: direct play, AVPlayer hands
///   them to the system compositor with the right metadata.
enum DirectPlayProfile {

    static func avPlayerProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 200_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,

            // ─── DirectPlay: containers AVPlayer can demux natively ───
            // Conservative codec list. HEVC Main10 (10-bit / HDR) and EAC3
            // multi-channel are intentionally excluded — see CodecProfiles
            // below — because Jellyfin's HLS remuxer produces manifests
            // for those that AVPlayer's HLS reader hangs on.
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

            // ─── Transcoding fallback: target HLS + fragmented MP4 ───
            // Jellyfin uses this when DirectPlay doesn't match. For MKV
            // containers with already-supported codecs, Jellyfin will
            // pick "remux" (Container=mp4, no codec change) automatically.
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "mp4",
                    "Protocol": "hls",
                    "VideoCodec": "h264,hevc",
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

            // ─── Container profiles: empty, no special remux rules ───
            "ContainerProfiles": [] as [Any],

            // ─── Codec-level constraints ───
            // Force the server to deliver SDR + 8-bit + stereo. The Apple
            // TV system setting "Match Dynamic Range" is OFF in our use
            // case, which means the Apple TV stays in SDR mode and would
            // have to client-side tone-map any incoming HDR stream — and
            // AVPlayer's HLS reader hangs on HEVC Main10 / HDR streams in
            // fragmented MP4 segments when that happens. Forcing the
            // server to do HDR→SDR tone mapping (via Jellyfin's HDR
            // tone-mapping pipeline) gives us a clean SDR stream that
            // AVPlayer plays reliably.
            //
            // The four constraints together:
            //   1. VideoRangeType = SDR        — explicit "no HDR / DV"
            //   2. VideoBitDepth ≤ 8           — forces 8-bit even if the
            //                                    source is 10-bit Main10
            //   3. VideoProfile = main         — HEVC profile cap
            //   4. AudioChannels ≤ 2           — downmix multi-channel
            //                                    (also avoids EAC3 Atmos
            //                                    HLS-remux issues)
            //
            // Trade-off: HDR is downgraded to SDR, Dolby Atmos to stereo.
            // Phase 2 will graduate this to a runtime decision based on
            // actual display + audio receiver capabilities.
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
            ] as [[String: Any]],

            // ─── Subtitles ───
            // External WebVTT works directly with AVPlayer / HLS.
            // Image-based subs (PGS, VobSub) and bitmap formats need
            // burn-in. Jellyfin handles the conversion.
            "SubtitleProfiles": [
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
            ] as [[String: Any]],
        ]
    }
}
