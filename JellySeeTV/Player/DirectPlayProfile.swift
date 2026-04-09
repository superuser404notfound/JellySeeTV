import Foundation

/// Builds device profiles for Jellyfin playback negotiation.
/// Two profiles: AVPlayer (primary, fast start) and VLCKit (fallback, universal).
enum DirectPlayProfile {

    /// AVPlayer profile: native containers + HLS remux for MKV
    static func avPlayerProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 120_000_000,
            "MaxStaticBitrate": 120_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,eac3,flac,alac,mp3",
                ],
                [
                    "Container": "mp3,aac,flac,alac,m4a,m4b,wav",
                    "Type": "Audio",
                ],
            ] as [[String: Any]],
            "TranscodingProfiles": [
                [
                    "Container": "mp4",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,ac3,eac3",
                    "Protocol": "hls",
                    "Context": "Streaming",
                    "MaxAudioChannels": "8",
                    "MinSegments": "2",
                    "BreakOnNonKeyFrames": true,
                    "CopyTimestamps": true,
                ],
            ] as [[String: Any]],
            "ContainerProfiles": [] as [Any],
            "CodecProfiles": [
                [
                    "Type": "Video",
                    "Codec": "h264",
                    "Conditions": [
                        condition("LessThanEqual", "Width", "3840"),
                        condition("LessThanEqual", "Height", "2160"),
                    ],
                ],
                [
                    "Type": "Video",
                    "Codec": "hevc",
                    "Conditions": [
                        condition("LessThanEqual", "Width", "3840"),
                        condition("LessThanEqual", "Height", "2160"),
                    ],
                ],
            ] as [[String: Any]],
            "SubtitleProfiles": [
                ["Format": "srt", "Method": "External"],
                ["Format": "ass", "Method": "External"],
                ["Format": "ssa", "Method": "External"],
                ["Format": "vtt", "Method": "External"],
                ["Format": "subrip", "Method": "External"],
                ["Format": "pgssub", "Method": "Embed"],
                ["Format": "dvdsub", "Method": "Embed"],
                ["Format": "pgs", "Method": "Embed"],
            ] as [[String: Any]],
        ]
    }

    /// VLCKit profile: plays everything
    static func vlcKitProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 200_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov,mkv,webm,avi,ts,mpg,mpeg,flv,wmv,ogv",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc,av1,vp8,vp9,mpeg2video,mpeg4,vc1,wmv3,theora",
                    "AudioCodec": "aac,ac3,eac3,flac,alac,opus,mp3,dts,truehd,vorbis,pcm_s16le,pcm_s24le",
                ],
            ] as [[String: Any]],
            "TranscodingProfiles": [] as [[String: Any]],
            "ContainerProfiles": [] as [Any],
            "CodecProfiles": [] as [[String: Any]],
            "SubtitleProfiles": [
                ["Format": "srt", "Method": "External"],
                ["Format": "ass", "Method": "External"],
                ["Format": "ssa", "Method": "External"],
                ["Format": "vtt", "Method": "External"],
                ["Format": "pgssub", "Method": "Embed"],
                ["Format": "dvdsub", "Method": "Embed"],
                ["Format": "pgs", "Method": "Embed"],
                ["Format": "dvbsub", "Method": "Embed"],
            ] as [[String: Any]],
        ]
    }

    static func condition(_ cond: String, _ property: String, _ value: String) -> [String: Any] {
        ["Condition": cond, "Property": property, "Value": value, "IsRequired": false]
    }
}
