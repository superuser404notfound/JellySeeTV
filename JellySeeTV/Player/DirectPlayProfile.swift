import Foundation

/// Builds the device profile JSON that tells Jellyfin what this device can play.
/// With VLCKit, we support virtually every format via DirectPlay.
enum DirectPlayProfile {

    static func build() -> [String: Any] {
        [
            "MaxStreamingBitrate": 200_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": directPlayProfiles,
            "TranscodingProfiles": transcodingProfiles,
            "ContainerProfiles": [] as [Any],
            "CodecProfiles": codecProfiles,
            "SubtitleProfiles": subtitleProfiles,
        ]
    }

    // MARK: - DirectPlay (VLCKit plays everything)

    private static var directPlayProfiles: [[String: Any]] {
        [
            [
                "Container": "mp4,m4v,mov,mkv,webm,avi,ts,mpg,mpeg,flv,3gp,wmv,ogv,ogg",
                "Type": "Video",
                "VideoCodec": "h264,hevc,av1,vp8,vp9,mpeg2video,mpeg4,msmpeg4v3,theora,vc1,wmv3",
                "AudioCodec": "aac,ac3,eac3,flac,alac,opus,mp3,mp2,vorbis,dts,truehd,pcm_s16le,pcm_s24le,wmav2",
            ],
            [
                "Container": "mp3,aac,flac,alac,m4a,m4b,ogg,opus,wav,wma",
                "Type": "Audio",
            ],
        ]
    }

    // MARK: - Transcoding (fallback, should rarely be needed)

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
        ]
    }

    // MARK: - Codec Profiles

    private static var codecProfiles: [[String: Any]] {
        [
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
            [
                "Type": "Video",
                "Codec": "av1",
                "Conditions": [
                    condition("LessThanEqual", "Width", "3840"),
                    condition("LessThanEqual", "Height", "2160"),
                ],
            ],
        ]
    }

    // MARK: - Subtitle Profiles (VLCKit renders all formats)

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
            ["Format": "dvbsub", "Method": "Embed"],
            ["Format": "idx", "Method": "External"],
        ]
    }

    // MARK: - Helpers

    private static func condition(_ condition: String, _ property: String, _ value: String) -> [String: Any] {
        [
            "Condition": condition,
            "Property": property,
            "Value": value,
            "IsRequired": false,
        ]
    }
}
