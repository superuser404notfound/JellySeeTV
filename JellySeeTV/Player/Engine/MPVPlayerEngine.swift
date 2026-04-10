import Foundation
import Observation
import QuartzCore
import UIKit
import AVFoundation
import Libmpv

/// The state of the player engine
enum EngineState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case seeking
    case error(String)
}

/// Info about an audio or subtitle track
struct TrackInfo: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let codec: String
    let language: String?
    let isDefault: Bool
}

/// libmpv-backed video player engine.
/// mpv handles demuxing, decoding (VideoToolbox HW), audio output, A/V sync,
/// seeking, subtitles, and HDR. We render via MoltenVK into a CAMetalLayer.
@Observable
@MainActor
final class MPVPlayerEngine {
    // MARK: - Public State

    var state: EngineState = .idle
    var currentTime: Double = 0
    var duration: Double = 0
    var progress: Float = 0
    var audioTracks: [TrackInfo] = []
    var subtitleTracks: [TrackInfo] = []
    var currentAudioTrackIndex: Int = -1
    var currentSubtitleTrackIndex: Int = -1

    /// The Metal layer mpv renders into. Add this to a UIView to display video.
    let metalLayer: CAMetalLayer = {
        let layer = CAMetalLayer()
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.backgroundColor = UIColor.black.cgColor
        layer.pixelFormat = .bgra8Unorm
        // Default drawable size — host view updates this on layout
        layer.drawableSize = CGSize(width: 1920, height: 1080)
        return layer
    }()

    // MARK: - Private

    nonisolated private let handleStorage = MPVHandleStorage()
    nonisolated private var mpvHandle: OpaquePointer? {
        let addr = handleStorage.value
        return addr == 0 ? nil : OpaquePointer(bitPattern: addr)
    }

    nonisolated private let eventQueue = DispatchQueue(label: "mpv.events", qos: .userInitiated)

    init() {}

    deinit {
        if let handle = mpvHandle {
            mpv_terminate_destroy(handle)
        }
    }

    // MARK: - Initialization

    private func initializeMpvIfNeeded() throws {
        guard mpvHandle == nil else { return }

        // Activate AVAudioSession before mpv (audiounit AO needs it)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[MPV] AVAudioSession error: \(error)")
            #endif
        }

        guard let handle = mpv_create() else {
            throw MPVError.createFailed
        }
        handleStorage.value = Int(bitPattern: handle)

        // ====== Pre-init options ======

        // Video output via MoltenVK rendering into our CAMetalLayer
        let widValue = Int64(Int(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
        var wid = widValue
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)

        setOption(handle, "vo", "gpu-next")
        setOption(handle, "gpu-api", "vulkan")
        setOption(handle, "gpu-context", "moltenvk")
        setOption(handle, "hwdec", "videotoolbox-copy")

        // Audio
        setOption(handle, "ao", "audiounit")
        // CRITICAL WORKAROUND: MPVKit's audiounit AO fails on tvOS with
        // "unable to retrieve audio unit channel layout" because AURemoteIO
        // doesn't expose kAudioUnitProperty_AudioChannelLayout. With this
        // option, mpv falls back to a null AO instead of bailing out — so
        // playback continues (silently) instead of failing entirely.
        setOption(handle, "audio-fallback-to-null", "yes")

        // No mpv config files, no built-in UI/input — we drive everything from Swift
        setOption(handle, "config", "no")
        setOption(handle, "idle", "yes")
        setOption(handle, "keep-open", "always")
        setOption(handle, "network-timeout", "10")

        // HDR / tone mapping
        setOption(handle, "tone-mapping", "bt.2446a")
        setOption(handle, "target-colorspace-hint", "yes")

        // Subtitles via libass
        setOption(handle, "sub-auto", "fuzzy")
        setOption(handle, "sub-font-size", "55")
        setOption(handle, "sub-color", "#FFFFFFFF")
        setOption(handle, "sub-border-color", "#FF000000")
        setOption(handle, "sub-border-size", "3")
        setOption(handle, "blend-subtitles", "yes")

        // Logging
        #if DEBUG
        mpv_request_log_messages(handle, "warn")
        #endif

        // ====== Initialize ======

        let ret = mpv_initialize(handle)
        guard ret >= 0 else {
            mpv_terminate_destroy(handle)
            handleStorage.value = 0
            throw MPVError.initFailed(String(cString: mpv_error_string(ret)))
        }

        // ====== Post-init: observers + wakeup callback ======

        observeProperty(handle, "time-pos", MPV_FORMAT_DOUBLE, userdata: 1)
        observeProperty(handle, "duration", MPV_FORMAT_DOUBLE, userdata: 2)
        observeProperty(handle, "pause", MPV_FORMAT_FLAG, userdata: 3)
        observeProperty(handle, "track-list", MPV_FORMAT_NODE, userdata: 4)
        observeProperty(handle, "seeking", MPV_FORMAT_FLAG, userdata: 5)
        observeProperty(handle, "core-idle", MPV_FORMAT_FLAG, userdata: 6)

        // Wakeup callback drives async event loop
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx = ctx else { return }
            let engine = Unmanaged<MPVPlayerEngine>.fromOpaque(ctx).takeUnretainedValue()
            engine.scheduleEventDrain()
        }, opaqueSelf)

        #if DEBUG
        print("[MPV] Initialized (full pipeline)")
        #endif
    }

    // MARK: - Public API

    /// Load a media URL. Replaces any current playback.
    func load(url: URL, startPosition: Double? = nil) async throws {
        try initializeMpvIfNeeded()
        guard let handle = mpvHandle else {
            throw MPVError.notInitialized
        }

        state = .loading
        currentTime = 0
        duration = 0
        progress = 0
        audioTracks = []
        subtitleTracks = []
        currentAudioTrackIndex = -1
        currentSubtitleTrackIndex = -1

        #if DEBUG
        print("[MPV] Loading: \(url.absoluteString)")
        #endif

        if let pos = startPosition, pos > 0 {
            command(handle, args: ["loadfile", url.absoluteString, "replace", "0", "start=\(pos)"])
        } else {
            command(handle, args: ["loadfile", url.absoluteString])
        }
        // State transitions to .playing via MPV_EVENT_FILE_LOADED in event loop
    }

    func play() {
        guard let handle = mpvHandle else { return }
        var flag: Int32 = 0
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
        state = .playing
    }

    func pause() {
        guard let handle = mpvHandle else { return }
        var flag: Int32 = 1
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
        state = .paused
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: play()
        default: break
        }
    }

    func seek(to seconds: Double) async {
        guard let handle = mpvHandle else { return }
        let target = max(0, seconds)
        state = .seeking
        #if DEBUG
        print("[MPV] Seek to \(String(format: "%.1f", target))s")
        #endif
        command(handle, args: ["seek", String(target), "absolute"])
    }

    func stop() {
        guard let handle = mpvHandle else { return }
        command(handle, args: ["stop"])
        state = .idle
        currentTime = 0
        progress = 0
    }

    func selectAudioTrack(index: Int) async {
        guard let handle = mpvHandle else { return }
        setProperty(handle, "aid", index < 0 ? "no" : String(index))
        currentAudioTrackIndex = index
    }

    func selectSubtitleTrack(index: Int) async {
        guard let handle = mpvHandle else { return }
        setProperty(handle, "sid", index < 0 ? "no" : String(index))
        currentSubtitleTrackIndex = index
    }

    // MARK: - Event Loop (runs on background thread)

    /// Called from mpv's wakeup callback.
    nonisolated fileprivate func scheduleEventDrain() {
        eventQueue.async { [weak self] in
            self?.drainEvents()
        }
    }

    private nonisolated func drainEvents() {
        guard let handle = mpvHandle else { return }
        while true {
            guard let eventPtr = mpv_wait_event(handle, 0) else { break }
            let event = eventPtr.pointee
            if event.event_id == MPV_EVENT_NONE { break }
            handleEvent(event)
        }
    }

    private nonisolated func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            #if DEBUG
            print("[MPV] FILE_LOADED")
            #endif
            Task { @MainActor [weak self] in
                self?.state = .playing
                self?.fetchTrackList()
            }

        case MPV_EVENT_END_FILE:
            let endData = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            #if DEBUG
            if let r = endData?.reason {
                print("[MPV] END_FILE reason=\(r.rawValue)")
            }
            #endif
            if endData?.reason == MPV_END_FILE_REASON_ERROR {
                let errCode = endData?.error ?? 0
                let errMsg = String(cString: mpv_error_string(errCode))
                Task { @MainActor [weak self] in
                    self?.state = .error("Playback failed: \(errMsg)")
                }
            } else if endData?.reason == MPV_END_FILE_REASON_EOF {
                Task { @MainActor [weak self] in
                    self?.state = .idle
                }
            }

        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event)

        case MPV_EVENT_LOG_MESSAGE:
            #if DEBUG
            if let logData = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee {
                let prefix = String(cString: logData.prefix)
                let level = String(cString: logData.level)
                let text = String(cString: logData.text).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    print("[mpv:\(level)/\(prefix)] \(text)")
                }
            }
            #endif

        case MPV_EVENT_SHUTDOWN:
            #if DEBUG
            print("[MPV] SHUTDOWN")
            #endif

        default:
            break
        }
    }

    private nonisolated func handlePropertyChange(_ event: mpv_event) {
        guard let propPtr = event.data?.assumingMemoryBound(to: mpv_event_property.self) else { return }
        let prop = propPtr.pointee
        let name = String(cString: prop.name)

        switch name {
        case "time-pos":
            if prop.format == MPV_FORMAT_DOUBLE, let dataPtr = prop.data {
                let value = dataPtr.assumingMemoryBound(to: Double.self).pointee
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentTime = value
                    if self.duration > 0 {
                        self.progress = Float(value / self.duration)
                    }
                }
            }

        case "duration":
            if prop.format == MPV_FORMAT_DOUBLE, let dataPtr = prop.data {
                let value = dataPtr.assumingMemoryBound(to: Double.self).pointee
                Task { @MainActor [weak self] in
                    self?.duration = value
                }
            }

        case "pause":
            if prop.format == MPV_FORMAT_FLAG, let dataPtr = prop.data {
                let isPaused = dataPtr.assumingMemoryBound(to: Int32.self).pointee != 0
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if case .seeking = self.state { return }
                    self.state = isPaused ? .paused : .playing
                }
            }

        case "track-list":
            Task { @MainActor [weak self] in
                self?.fetchTrackList()
            }

        case "seeking":
            if prop.format == MPV_FORMAT_FLAG, let dataPtr = prop.data {
                let isSeeking = dataPtr.assumingMemoryBound(to: Int32.self).pointee != 0
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if isSeeking {
                        self.state = .seeking
                    } else if let handle = self.mpvHandle {
                        var flag: Int32 = 0
                        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
                        self.state = flag != 0 ? .paused : .playing
                    }
                }
            }

        default:
            break
        }
    }

    // MARK: - Track List

    private func fetchTrackList() {
        guard let handle = mpvHandle else { return }
        var node = mpv_node()
        let ret = mpv_get_property(handle, "track-list", MPV_FORMAT_NODE, &node)
        guard ret >= 0 else { return }
        defer { mpv_free_node_contents(&node) }

        var audio: [TrackInfo] = []
        var subs: [TrackInfo] = []
        var selectedAudio = -1
        var selectedSub = -1

        guard node.format == MPV_FORMAT_NODE_ARRAY, let listPtr = node.u.list else { return }
        let list = listPtr.pointee
        for i in 0..<Int(list.num) {
            guard let valuesPtr = list.values else { continue }
            let item = valuesPtr[i]
            guard item.format == MPV_FORMAT_NODE_MAP, let mapPtr = item.u.list else { continue }
            let map = mapPtr.pointee

            var id = 0
            var type = ""
            var lang: String? = nil
            var title: String? = nil
            var codec = ""
            var isDefault = false
            var isSelected = false

            for j in 0..<Int(map.num) {
                guard let keys = map.keys, let values = map.values else { continue }
                guard let keyPtr = keys[j] else { continue }
                let key = String(cString: keyPtr)
                let v = values[j]
                switch key {
                case "id":
                    if v.format == MPV_FORMAT_INT64 { id = Int(v.u.int64) }
                case "type":
                    if v.format == MPV_FORMAT_STRING, let s = v.u.string {
                        type = String(cString: s)
                    }
                case "lang":
                    if v.format == MPV_FORMAT_STRING, let s = v.u.string {
                        lang = String(cString: s)
                    }
                case "title":
                    if v.format == MPV_FORMAT_STRING, let s = v.u.string {
                        title = String(cString: s)
                    }
                case "codec":
                    if v.format == MPV_FORMAT_STRING, let s = v.u.string {
                        codec = String(cString: s)
                    }
                case "default":
                    if v.format == MPV_FORMAT_FLAG { isDefault = v.u.flag != 0 }
                case "selected":
                    if v.format == MPV_FORMAT_FLAG { isSelected = v.u.flag != 0 }
                default:
                    break
                }
            }

            let info = TrackInfo(
                id: id,
                name: title ?? lang ?? "Track \(id)",
                codec: codec,
                language: lang,
                isDefault: isDefault
            )

            if type == "audio" {
                audio.append(info)
                if isSelected { selectedAudio = id }
            } else if type == "sub" {
                subs.append(info)
                if isSelected { selectedSub = id }
            }
        }

        self.audioTracks = audio
        self.subtitleTracks = subs
        self.currentAudioTrackIndex = selectedAudio
        self.currentSubtitleTrackIndex = selectedSub

        #if DEBUG
        print("[MPV] Tracks: \(audio.count) audio, \(subs.count) subs")
        #endif
    }

    // MARK: - mpv Helpers

    private nonisolated func setOption(_ handle: OpaquePointer, _ name: String, _ value: String) {
        let ret = mpv_set_option_string(handle, name, value)
        if ret < 0 {
            #if DEBUG
            print("[MPV] setOption(\(name)=\(value)) failed: \(String(cString: mpv_error_string(ret)))")
            #endif
        }
    }

    private nonisolated func setProperty(_ handle: OpaquePointer, _ name: String, _ value: String) {
        let ret = mpv_set_property_string(handle, name, value)
        if ret < 0 {
            #if DEBUG
            print("[MPV] setProperty(\(name)=\(value)) failed: \(String(cString: mpv_error_string(ret)))")
            #endif
        }
    }

    private nonisolated func observeProperty(_ handle: OpaquePointer, _ name: String, _ format: mpv_format, userdata: UInt64) {
        mpv_observe_property(handle, userdata, name, format)
    }

    private nonisolated func command(_ handle: OpaquePointer, args: [String]) {
        // strdup keeps the C strings alive across the mpv_command call
        let cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer {
            for ptr in cStrings { if let p = ptr { free(p) } }
        }
        var ptrs: [UnsafePointer<CChar>?] = cStrings.map { $0.map { UnsafePointer($0) } }
        ptrs.append(nil)
        let ret = ptrs.withUnsafeMutableBufferPointer { buf in
            mpv_command(handle, buf.baseAddress)
        }
        if ret < 0 {
            #if DEBUG
            print("[MPV] command(\(args.first ?? "?")) failed: \(String(cString: mpv_error_string(ret)))")
            #endif
        }
    }
}

// MARK: - Storage

/// Thread-safe storage for the mpv handle address.
/// Int writes are atomic on 64-bit Apple platforms.
nonisolated final class MPVHandleStorage: @unchecked Sendable {
    nonisolated(unsafe) var value: Int = 0
}

// MARK: - Errors

enum MPVError: LocalizedError {
    case createFailed
    case initFailed(String)
    case notInitialized
    case loadFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .createFailed: "Failed to create mpv instance"
        case .initFailed(let msg): "Failed to initialize mpv: \(msg)"
        case .notInitialized: "mpv not initialized"
        case .loadFailed(let msg): "Failed to load media: \(msg)"
        case .commandFailed(let msg): "mpv command failed: \(msg)"
        }
    }
}
