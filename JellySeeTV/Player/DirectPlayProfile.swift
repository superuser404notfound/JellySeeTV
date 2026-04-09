import Foundation
import VideoToolbox

/// Builds the device profile JSON that tells Jellyfin what this Apple TV can play natively.
enum DirectPlayProfile {

    /// Whether this device has hardware AV1 decode (Apple TV 4K 3rd gen 2022+)
    static let supportsAV1Hardware: Bool = {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }()

    static func build() -> [String: Any] {
        [
            "MaxStreamingBitrate": 120_000_000,
            "MaxStaticBitrate": 120_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": directPlayProfiles,
            "TranscodingProfiles": transcodingProfiles,
            "ContainerProfiles": [] as [Any],
            "CodecProfiles": codecProfiles,
            "SubtitleProfiles": subtitleProfiles,
        ]
    }

    // MARK: - DirectPlay (what we can play natively)

    private static var videoCodecs: String {
        var codecs = ["h264", "hevc", "vp9"]
        if supportsAV1Hardware {
            codecs.append("av1")
        }
        return codecs.joined(separator: ",")
    }

    private static var directPlayProfiles: [[String: Any]] {
        [
            [
                "Container": "mp4,m4v,mov,mkv,webm",
                "Type": "Video",
                "VideoCodec": videoCodecs,
                "AudioCodec": "aac,ac3,eac3,flac,alac,opus,mp3,vorbis,pcm_s16le,pcm_s24le",
            ],
            [
                "Container": "mp3,aac,flac,alac,m4a,m4b,ogg,opus,wav",
                "Type": "Audio",
            ],
        ]
    }

    // MARK: - Transcoding (fallback when DirectPlay not possible)

    private static var transcodingProfiles: [[String: Any]] {
        [
            [
                "Container": "mp4",
                "Type": "Video",
                "VideoCodec": "h264,hevc",
                "AudioCodec": "aac,ac3,eac3",
                "Protocol": "hls",
                "Context": "Streaming",
                "MaxAudioChannels": "6",
                "MinSegments": "2",
                "BreakOnNonKeyFrames": true,
                "CopyTimestamps": true,
            ],
            [
                "Container": "mp3",
                "Type": "Audio",
                "AudioCodec": "mp3",
                "Protocol": "http",
                "Context": "Streaming",
            ],
        ]
    }

    // MARK: - Codec Profiles (detailed capabilities)

    private static var codecProfiles: [[String: Any]] {
        var profiles: [[String: Any]] = [
            // H.264 limits
            [
                "Type": "Video",
                "Codec": "h264",
                "Conditions": [
                    condition("LessThanEqual", "Width", "3840"),
                    condition("LessThanEqual", "Height", "2160"),
                    condition("LessThanEqual", "VideoLevel", "52"),
                    condition("NotEquals", "IsAnamorphic", "true"),
                ],
            ],
            // HEVC limits
            [
                "Type": "Video",
                "Codec": "hevc",
                "Conditions": [
                    condition("LessThanEqual", "Width", "3840"),
                    condition("LessThanEqual", "Height", "2160"),
                    condition("LessThanEqual", "VideoLevel", "186"),
                ],
            ],
        ]

        // AV1 only if hardware decode available
        if supportsAV1Hardware {
            profiles.append([
                "Type": "Video",
                "Codec": "av1",
                "Conditions": [
                    condition("LessThanEqual", "Width", "3840"),
                    condition("LessThanEqual", "Height", "2160"),
                ],
            ])
        }

        return profiles
    }

    // MARK: - Subtitle Profiles

    private static var subtitleProfiles: [[String: Any]] {
        [
            ["Format": "srt", "Method": "External"],
            ["Format": "ass", "Method": "External"],
            ["Format": "ssa", "Method": "External"],
            ["Format": "vtt", "Method": "External"],
            ["Format": "sub", "Method": "External"],
            ["Format": "subrip", "Method": "External"],
            ["Format": "pgssub", "Method": "Embed"],
            ["Format": "dvdsub", "Method": "Embed"],
            ["Format": "pgs", "Method": "Embed"],
        ]
    }

    // MARK: - Helpers

    private static func condition(_ condition: String, _ property: String, _ value: String) -> [String: String] {
        [
            "Condition": condition,
            "Property": property,
            "Value": value,
            "IsRequired": "false",
        ]
    }
}
