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
        // Set a default drawable size so mpv has something to work with
        // before the host view has actually laid out. The host view will
        // update this once it has real bounds.
        layer.drawableSize = CGSize(width: 1920, height: 1080)
        return layer
    }()

    // MARK: - Private

    /// Use Int to avoid Sendable issues with raw pointers across actor boundaries.
    /// Atomic access via OSAllocatedUnfairLock would be ideal but Int writes are
    /// atomic on 64-bit Apple platforms, so plain nonisolated is safe enough here.
    nonisolated private let _mpvHandleAddress = MPVHandleStorage()
    nonisolated private var mpvHandleAddress: Int {
        get { _mpvHandleAddress.value }
        set { _mpvHandleAddress.value = newValue }
    }

    private var mpvHandle: OpaquePointer? {
        get { mpvHandleAddress == 0 ? nil : OpaquePointer(bitPattern: mpvHandleAddress) }
        set { mpvHandleAddress = newValue.map { Int(bitPattern: $0) } ?? 0 }
    }

    nonisolated private let eventQueue = DispatchQueue(label: "mpv.events", qos: .userInitiated)

    init() {}

    deinit {
        if mpvHandleAddress != 0, let handle = OpaquePointer(bitPattern: mpvHandleAddress) {
            mpv_terminate_destroy(handle)
        }
    }

    // MARK: - Lifecycle

    /// Initialize the mpv instance with our chosen options. Called once before first load.
    private func initializeMpvIfNeeded() throws {
        guard mpvHandle == nil else { return }

        // Activate AVAudioSession for mpv's audiounit AO
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            #if DEBUG
            print("[MPV] AVAudioSession active")
            #endif
        } catch {
            #if DEBUG
            print("[MPV] AVAudioSession error: \(error)")
            #endif
        }

        guard let handle = mpv_create() else {
            throw MPVError.createFailed
        }
        mpvHandle = handle

        // Audio enabled, video still null
        setOption(handle, "vo", "null")
        setOption(handle, "ao", "audiounit")
        setOption(handle, "vid", "no")
        setOption(handle, "aid", "auto")
        setOption(handle, "config", "no")
        setOption(handle, "idle", "yes")
        // Force stereo to bypass MPVKit's audiounit channel layout query
        // (kAudioUnitProperty_AudioChannelLayout isn't supported by AURemoteIO on tvOS)
        setOption(handle, "audio-channels", "stereo")

        #if DEBUG
        mpv_request_log_messages(handle, "v")  // verbose for diagnosis
        #endif

        let ret = mpv_initialize(handle)
        guard ret >= 0 else {
            mpv_terminate_destroy(handle)
            mpvHandle = nil
            throw MPVError.initFailed(String(cString: mpv_error_string(ret)))
        }

        #if DEBUG
        print("[MPV] Initialized (test: aid=auto, ao=audiounit)")
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

        command(handle, args: ["loadfile", url.absoluteString])

        #if DEBUG
        // Synchronous drain for 2 seconds — show ALL log messages
        print("[MPV] Draining events for 3s...")
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            guard let eventPtr = mpv_wait_event(handle, 0.05) else { continue }
            let event = eventPtr.pointee
            if event.event_id == MPV_EVENT_NONE { continue }
            if event.event_id == MPV_EVENT_LOG_MESSAGE {
                if let logData = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee {
                    let prefix = String(cString: logData.prefix)
                    let level = String(cString: logData.level)
                    let text = String(cString: logData.text).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        print("[mpv:\(level)/\(prefix)] \(text)")
                    }
                }
            } else {
                print("[MPV] event id=\(event.event_id.rawValue)")
            }
        }
        print("[MPV] Drain complete")
        #endif
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
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        state = .seeking
        #if DEBUG
        print("[MPV] Seek to \(String(format: "%.1f", target))s")
        #endif
        command(handle, args: ["seek", String(target), "absolute"])
        // State will return to .playing/.paused via property observer
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
        // index is the mpv track id (1-based for tracks, "no" for off)
        if index < 0 {
            setProperty(handle, "aid", "no")
        } else {
            setProperty(handle, "aid", String(index))
        }
        currentAudioTrackIndex = index
    }

    func selectSubtitleTrack(index: Int) async {
        guard let handle = mpvHandle else { return }
        if index < 0 {
            setProperty(handle, "sid", "no")
        } else {
            setProperty(handle, "sid", String(index))
        }
        currentSubtitleTrackIndex = index
    }

    // MARK: - Event Loop

    /// Called from mpv's wakeup callback (background thread).
    /// Must be nonisolated since the callback runs off the MainActor.
    nonisolated fileprivate func scheduleEventDrain() {
        eventQueue.async { [weak self] in
            self?.drainEvents()
        }
    }

    private nonisolated func drainEvents() {
        guard let handle = OpaquePointer(bitPattern: mpvHandleAddress) else { return }
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
            Task { @MainActor in
                self.state = .playing
                self.fetchTrackList()
            }

        case MPV_EVENT_END_FILE:
            let endData = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            let reason = endData?.reason
            #if DEBUG
            print("[MPV] END_FILE reason=\(String(describing: reason))")
            #endif
            if reason == MPV_END_FILE_REASON_ERROR {
                let errCode = endData?.error ?? 0
                let errMsg = String(cString: mpv_error_string(errCode))
                Task { @MainActor in
                    self.state = .error("Playback failed: \(errMsg)")
                }
            } else if reason == MPV_END_FILE_REASON_EOF {
                Task { @MainActor in
                    self.state = .idle
                }
            }

        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event)

        case MPV_EVENT_LOG_MESSAGE:
            #if DEBUG
            if let logData = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee {
                let prefix = String(cString: logData.prefix)
                let text = String(cString: logData.text).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    print("[MPV:\(prefix)] \(text)")
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
                Task { @MainActor in
                    self.currentTime = value
                    if self.duration > 0 {
                        self.progress = Float(value / self.duration)
                    }
                }
            }

        case "duration":
            if prop.format == MPV_FORMAT_DOUBLE, let dataPtr = prop.data {
                let value = dataPtr.assumingMemoryBound(to: Double.self).pointee
                Task { @MainActor in
                    self.duration = value
                }
            }

        case "pause":
            if prop.format == MPV_FORMAT_FLAG, let dataPtr = prop.data {
                let isPaused = dataPtr.assumingMemoryBound(to: Int32.self).pointee != 0
                Task { @MainActor in
                    if case .seeking = self.state { return }
                    self.state = isPaused ? .paused : .playing
                }
            }

        case "track-list":
            Task { @MainActor in
                self.fetchTrackList()
            }

        case "seeking":
            if prop.format == MPV_FORMAT_FLAG, let dataPtr = prop.data {
                let isSeeking = dataPtr.assumingMemoryBound(to: Int32.self).pointee != 0
                Task { @MainActor in
                    if isSeeking {
                        self.state = .seeking
                    } else {
                        // Re-read pause to determine post-seek state
                        if let handle = self.mpvHandle {
                            var flag: Int32 = 0
                            mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
                            self.state = flag != 0 ? .paused : .playing
                        }
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
                    if v.format == MPV_FORMAT_INT64 {
                        id = Int(v.u.int64)
                    }
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
                    if v.format == MPV_FORMAT_FLAG {
                        isDefault = v.u.flag != 0
                    }
                case "selected":
                    if v.format == MPV_FORMAT_FLAG {
                        isSelected = v.u.flag != 0
                    }
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

    private nonisolated func command(_ handle: OpaquePointer, args: [String], completion: ((Error?) -> Void)? = nil) {
        // Use strdup to ensure each C string outlives the mpv_command call.
        // (NSString).utf8String returns an autoreleased pointer that may be freed
        // before mpv_command runs, causing crashes.
        let cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer {
            for ptr in cStrings { if let p = ptr { free(p) } }
        }
        // Build NULL-terminated array of UnsafePointer<CChar>?
        var ptrs: [UnsafePointer<CChar>?] = cStrings.map { $0.map { UnsafePointer($0) } }
        ptrs.append(nil)
        let ret = ptrs.withUnsafeMutableBufferPointer { buf -> Int32 in
            mpv_command(handle, buf.baseAddress)
        }
        if ret < 0 {
            let msg = String(cString: mpv_error_string(ret))
            #if DEBUG
            print("[MPV] command(\(args.first ?? "?")) failed: \(msg)")
            #endif
            completion?(MPVError.commandFailed(msg))
        } else {
            completion?(nil)
        }
    }
}

// MARK: - Storage

/// Thread-safe storage for the mpv handle address.
/// Int writes are atomic on 64-bit, so no lock needed.
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
