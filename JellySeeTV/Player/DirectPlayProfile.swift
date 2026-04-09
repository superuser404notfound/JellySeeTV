import Foundation

/// Device profile for custom FFmpeg engine: DirectPlay everything.
/// No transcoding needed -- the engine handles all formats natively.
enum DirectPlayProfile {

    static func customEngineProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 200_000_000,
            "MaxStaticBitrate": 200_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov,mkv,webm,avi,ts,mpg,mpeg,flv,wmv,ogv,ogg",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc,av1,vp8,vp9,mpeg2video,mpeg4,msmpeg4v3,theora,vc1,wmv3",
                    "AudioCodec": "aac,ac3,eac3,flac,alac,opus,mp3,dts,truehd,vorbis,pcm_s16le,pcm_s24le,wmav2",
                ],
                [
                    "Container": "mp3,aac,flac,alac,m4a,m4b,ogg,opus,wav,wma",
                    "Type": "Audio",
                ],
            ] as [[String: Any]],
            "TranscodingProfiles": [] as [[String: Any]], // Never transcode
            "ContainerProfiles": [] as [Any],
            "CodecProfiles": [] as [[String: Any]],
            "SubtitleProfiles": [
                ["Format": "srt", "Method": "Embed"],
                ["Format": "ass", "Method": "Embed"],
                ["Format": "ssa", "Method": "Embed"],
                ["Format": "vtt", "Method": "External"],
                ["Format": "subrip", "Method": "Embed"],
                ["Format": "pgssub", "Method": "Embed"],
                ["Format": "dvdsub", "Method": "Embed"],
                ["Format": "pgs", "Method": "Embed"],
                ["Format": "dvbsub", "Method": "Embed"],
            ] as [[String: Any]],
        ]
    }
}
