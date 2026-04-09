import Foundation
#if !targetEnvironment(simulator)
import CFFmpeg
#endif

/// Stream info extracted from the container
#if !targetEnvironment(simulator)
struct StreamInfo: Sendable {
    let index: Int32
    let type: PacketStreamType
    let codecID: UInt32       // AVCodecID raw value
    let codecName: String
    let language: String?
    let title: String?
    let isDefault: Bool

    // Video specific
    let width: Int32?
    let height: Int32?
    let frameRate: Double?

    // Audio specific
    let sampleRate: Int32?
    let channels: Int32?
    let channelLayout: String?
}

/// FFmpeg-based container demuxer. Opens any container format via HTTP
/// and provides packet-level access to audio, video, and subtitle streams.
nonisolated final class Demuxer: @unchecked Sendable {
    /// Stored as Int for Swift 6 deinit compatibility
    private var formatCtxAddress: Int = 0
    private var formatCtx: UnsafeMutablePointer<AVFormatContext>? {
        get { UnsafeMutablePointer(bitPattern: formatCtxAddress) }
        set { formatCtxAddress = newValue.map { Int(bitPattern: $0) } ?? 0 }
    }
    private let queue = DispatchQueue(label: "demuxer", qos: .userInitiated)
    private var isOpen = false

    // Selected stream indices
    private(set) var videoStreamIndex: Int32 = -1
    private(set) var audioStreamIndex: Int32 = -1
    private(set) var subtitleStreamIndex: Int32 = -1

    // All available streams
    private(set) var videoStreams: [StreamInfo] = []
    private(set) var audioStreams: [StreamInfo] = []
    private(set) var subtitleStreams: [StreamInfo] = []

    /// Duration in seconds
    private(set) var duration: Double = 0

    init() {
        // Register all formats and codecs once
        // (No-op in newer FFmpeg but safe to call)
    }

    // MARK: - Open

    /// Opens a media URL and probes stream info.
    /// When `skipProbe` is true, skips `avformat_find_stream_info` entirely
    /// (use when codec info is already known from Jellyfin PlaybackInfo).
    func open(url: URL, skipProbe: Bool = false) throws {
        try queue.sync {
            var ctx: UnsafeMutablePointer<AVFormatContext>?

            let urlString = url.absoluteString
            #if DEBUG
            print("[Demuxer] Opening URL: \(urlString) (skipProbe: \(skipProbe))")
            let openStart = CFAbsoluteTimeGetCurrent()
            #endif

            // Minimal options for fast HTTP open
            var opts: OpaquePointer?
            av_dict_set(&opts, "analyzeduration", "0", 0)
            av_dict_set(&opts, "probesize", "32768", 0)     // 32KB — just MKV/MP4 headers
            av_dict_set(&opts, "fflags", "fastseek", 0)
            av_dict_set(&opts, "reconnect", "1", 0)
            av_dict_set(&opts, "reconnect_streamed", "1", 0)

            var ret = avformat_open_input(&ctx, urlString, nil, &opts)
            av_dict_free(&opts)
            guard ret >= 0, let ctx else {
                let err = errorString(ret)
                #if DEBUG
                print("[Demuxer] FAILED to open: \(err) (code: \(ret))")
                #endif
                throw DemuxerError.openFailed(err)
            }
            formatCtx = ctx

            #if DEBUG
            let openTime = CFAbsoluteTimeGetCurrent() - openStart
            print("[Demuxer] avformat_open_input: \(String(format: "%.3f", openTime))s")
            #endif

            if !skipProbe {
                #if DEBUG
                let probeStart = CFAbsoluteTimeGetCurrent()
                #endif
                ctx.pointee.max_analyze_duration = 500_000 // 0.5s max
                ret = avformat_find_stream_info(ctx, nil)
                guard ret >= 0 else {
                    throw DemuxerError.streamInfoFailed(errorString(ret))
                }
                #if DEBUG
                let probeTime = CFAbsoluteTimeGetCurrent() - probeStart
                print("[Demuxer] avformat_find_stream_info: \(String(format: "%.3f", probeTime))s")
                #endif
            } else {
                // Minimal probe: just read enough for the container to detect streams
                // MKV/MP4 headers contain codec info, no need to decode packets
                ctx.pointee.max_analyze_duration = 0
                ret = avformat_find_stream_info(ctx, nil)
                // Ignore errors — stream info may be incomplete but usable
                #if DEBUG
                print("[Demuxer] Fast probe (skipProbe): ret=\(ret), streams=\(ctx.pointee.nb_streams)")
                #endif
            }

            // Extract duration (container level, or fallback to longest stream)
            let dur = ctx.pointee.duration
            let nopts = Int64(bitPattern: UInt64(0x8000000000000000))
            if dur > 0 && dur != nopts {
                duration = Double(dur) / Double(AV_TIME_BASE)
            } else {
                // MKV over HTTP may not have container duration — check streams
                let nbStreams = Int(ctx.pointee.nb_streams)
                for i in 0..<nbStreams {
                    guard let stream = ctx.pointee.streams[i] else { continue }
                    let sDur = stream.pointee.duration
                    if sDur > 0 && sDur != nopts {
                        let tb = stream.pointee.time_base
                        let streamDurSec = Double(sDur) * av_q2d(tb)
                        if streamDurSec > duration { duration = streamDurSec }
                    }
                }
            }

            #if DEBUG
            print("[Demuxer] nb_streams: \(ctx.pointee.nb_streams), raw duration: \(dur)")
            #endif

            // Enumerate streams
            let nbStreams = Int(ctx.pointee.nb_streams)
            for i in 0..<nbStreams {
                guard let stream = ctx.pointee.streams[i] else { continue }
                guard let codecparPtr = stream.pointee.codecpar else {
                    #if DEBUG
                    print("[Demuxer] Stream[\(i)]: codecpar is nil, skipping")
                    #endif
                    continue
                }
                let codecpar = codecparPtr.pointee

                #if DEBUG
                print("[Demuxer] Stream[\(i)]: codec_type=\(codecpar.codec_type.rawValue), codec_id=\(codecpar.codec_id.rawValue)")
                #endif

                let info = extractStreamInfo(stream: stream, index: Int32(i))

                switch codecpar.codec_type {
                case AVMEDIA_TYPE_VIDEO:
                    videoStreams.append(info)
                    if videoStreamIndex < 0 || info.isDefault {
                        videoStreamIndex = Int32(i)
                    }
                case AVMEDIA_TYPE_AUDIO:
                    audioStreams.append(info)
                    if audioStreamIndex < 0 || info.isDefault {
                        audioStreamIndex = Int32(i)
                    }
                case AVMEDIA_TYPE_SUBTITLE:
                    subtitleStreams.append(info)
                    if subtitleStreamIndex < 0 || info.isDefault {
                        subtitleStreamIndex = Int32(i)
                    }
                default:
                    break
                }
            }

            isOpen = true

            #if DEBUG
            print("[Demuxer] Opened: \(url.lastPathComponent)")
            print("[Demuxer] Duration: \(String(format: "%.1f", duration))s")
            print("[Demuxer] Video streams: \(videoStreams.count), Audio: \(audioStreams.count), Subtitle: \(subtitleStreams.count)")
            for vs in videoStreams {
                print("[Demuxer]   Video[\(vs.index)]: \(vs.codecName) \(vs.width ?? 0)x\(vs.height ?? 0) @\(String(format: "%.2f", vs.frameRate ?? 0))fps")
            }
            for as_ in audioStreams {
                print("[Demuxer]   Audio[\(as_.index)]: \(as_.codecName) \(as_.channels ?? 0)ch \(as_.sampleRate ?? 0)Hz \(as_.language ?? "?")")
            }
            for ss in subtitleStreams {
                print("[Demuxer]   Sub[\(ss.index)]: \(ss.codecName) \(ss.language ?? "?")")
            }
            #endif
        }
    }

    // MARK: - Read Packets

    /// Reads the next packet from the container. Returns nil only at true EOF.
    /// Retries on temporary errors (network buffering, EAGAIN).
    func readPacket() -> DemuxedPacket? {
        guard isOpen, let ctx = formatCtx else { return nil }

        let pkt = av_packet_alloc()!
        defer {
            var p: UnsafeMutablePointer<AVPacket>? = pkt
            av_packet_free(&p)
        }

        // Retry loop for temporary errors
        var ret: Int32 = 0
        var retries = 0
        let maxRetries = 50 // ~5 seconds of retries

        repeat {
            ret = av_read_frame(ctx, pkt)
            if ret >= 0 { break } // Success

            #if DEBUG
            if retries == 0 {
                print("[Demuxer] av_read_frame error: \(ret) (\(errorString(ret)))")
            }
            #endif

            let averror_eof = Int32(-541478725) // AVERROR_EOF
            if ret == averror_eof {
                #if DEBUG
                print("[Demuxer] True EOF reached")
                #endif
                return nil
            }

            // Retry on temporary errors
            retries += 1
            if retries <= maxRetries {
                Thread.sleep(forTimeInterval: 0.1) // Wait 100ms before retry
                #if DEBUG
                if retries % 10 == 0 {
                    print("[Demuxer] Read retry \(retries)/\(maxRetries), error: \(ret)")
                }
                #endif
            }
        } while retries <= maxRetries

        guard ret >= 0 else {
            #if DEBUG
            print("[Demuxer] Read failed after \(retries) retries, error: \(ret) (\(errorString(ret)))")
            #endif
            return nil
        }

        let streamIdx = pkt.pointee.stream_index
        let stream = ctx.pointee.streams[Int(streamIdx)]!
        let timeBase = stream.pointee.time_base

        // Convert PTS to seconds
        let pts: Double
        if pkt.pointee.pts != Int64(bitPattern: UInt64(0x8000000000000000)) {
            pts = Double(pkt.pointee.pts) * av_q2d(timeBase)
        } else if pkt.pointee.dts != Int64(bitPattern: UInt64(0x8000000000000000)) {
            pts = Double(pkt.pointee.dts) * av_q2d(timeBase)
        } else {
            pts = 0
        }

        let dur = Double(pkt.pointee.duration) * av_q2d(timeBase)

        // Determine stream type
        let type: PacketStreamType
        if streamIdx == videoStreamIndex {
            type = .video
        } else if streamIdx == audioStreamIndex {
            type = .audio
        } else if subtitleStreams.contains(where: { $0.index == streamIdx }) {
            type = .subtitle
        } else {
            return nil // Skip unknown streams
        }

        return DemuxedPacket(packet: pkt, streamType: type, streamIndex: streamIdx, pts: pts, duration: dur)
    }

    // MARK: - Seek

    /// Seeks to the nearest keyframe before the target time
    func seek(to seconds: Double) throws {
        guard isOpen, let ctx = formatCtx else { return }

        let timestamp = Int64(seconds * Double(AV_TIME_BASE))
        let ret = avformat_seek_file(ctx, -1, Int64.min, timestamp, timestamp, 0)
        guard ret >= 0 else {
            throw DemuxerError.seekFailed(errorString(ret))
        }
    }

    // MARK: - Stream Selection

    func selectAudioStream(index: Int32) {
        audioStreamIndex = index
    }

    func selectSubtitleStream(index: Int32) {
        subtitleStreamIndex = index
    }

    // MARK: - Codec Parameters

    /// Returns codec parameters for a stream (needed to init decoders)
    func codecParameters(for streamIndex: Int32) -> UnsafeMutablePointer<AVCodecParameters>? {
        guard let ctx = formatCtx, streamIndex >= 0,
              streamIndex < ctx.pointee.nb_streams else { return nil }
        return ctx.pointee.streams[Int(streamIndex)]!.pointee.codecpar
    }

    /// Returns the time base for a stream
    func timeBase(for streamIndex: Int32) -> AVRational {
        guard let ctx = formatCtx, streamIndex >= 0,
              streamIndex < ctx.pointee.nb_streams else { return AVRational(num: 1, den: 1) }
        return ctx.pointee.streams[Int(streamIndex)]!.pointee.time_base
    }

    // MARK: - Close

    func close() {
        queue.sync {
            if formatCtx != nil {
                avformat_close_input(&formatCtx)
            }
            isOpen = false
            videoStreams = []
            audioStreams = []
            subtitleStreams = []
            videoStreamIndex = -1
            audioStreamIndex = -1
            subtitleStreamIndex = -1
        }
    }

    nonisolated deinit {
        var ptr: UnsafeMutablePointer<AVFormatContext>? = UnsafeMutablePointer(bitPattern: formatCtxAddress)
        if ptr != nil {
            avformat_close_input(&ptr)
        }
    }

    // MARK: - Helpers

    private func extractStreamInfo(stream: UnsafeMutablePointer<AVStream>, index: Int32) -> StreamInfo {
        let codecpar = stream.pointee.codecpar!.pointee
        let metadata = stream.pointee.metadata

        // Get codec name
        let codecDesc = avcodec_descriptor_get(codecpar.codec_id)
        let codecName = codecDesc != nil ? String(cString: codecDesc!.pointee.name) : "unknown"

        // Get metadata tags
        let language = metadataValue(metadata, key: "language")
        let title = metadataValue(metadata, key: "title")

        // Check if default
        let isDefault = (stream.pointee.disposition & AV_DISPOSITION_DEFAULT) != 0

        // Video specific
        var width: Int32? = nil
        var height: Int32? = nil
        var frameRate: Double? = nil
        if codecpar.codec_type == AVMEDIA_TYPE_VIDEO {
            width = codecpar.width
            height = codecpar.height
            let fps = av_q2d(stream.pointee.avg_frame_rate)
            if fps > 0 { frameRate = fps }
        }

        // Audio specific
        var sampleRate: Int32? = nil
        var channels: Int32? = nil
        var channelLayout: String? = nil
        if codecpar.codec_type == AVMEDIA_TYPE_AUDIO {
            sampleRate = codecpar.sample_rate
            channels = codecpar.ch_layout.nb_channels
            // Channel layout string
            var buf = [CChar](repeating: 0, count: 64)
            av_channel_layout_describe(&stream.pointee.codecpar.pointee.ch_layout, &buf, 64)
            channelLayout = String(cString: buf)
        }

        return StreamInfo(
            index: index,
            type: codecpar.codec_type == AVMEDIA_TYPE_VIDEO ? .video :
                  codecpar.codec_type == AVMEDIA_TYPE_AUDIO ? .audio : .subtitle,
            codecID: codecpar.codec_id.rawValue,
            codecName: codecName,
            language: language,
            title: title,
            isDefault: isDefault,
            width: width,
            height: height,
            frameRate: frameRate,
            sampleRate: sampleRate,
            channels: channels,
            channelLayout: channelLayout
        )
    }

    private func metadataValue(_ metadata: OpaquePointer?, key: String) -> String? {
        guard let metadata else { return nil }
        var tag: UnsafeMutablePointer<AVDictionaryEntry>?
        tag = av_dict_get(metadata, key, nil, 0)
        guard let value = tag?.pointee.value else { return nil }
        return String(cString: value)
    }

    private func errorString(_ errnum: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        av_strerror(errnum, &buf, 256)
        return String(cString: buf)
    }
}

// MARK: - Errors

enum DemuxerError: LocalizedError {
    case openFailed(String)
    case streamInfoFailed(String)
    case seekFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): "Failed to open media: \(msg)"
        case .streamInfoFailed(let msg): "Failed to read stream info: \(msg)"
        case .seekFailed(let msg): "Seek failed: \(msg)"
        }
    }
}
#endif // !targetEnvironment(simulator)
