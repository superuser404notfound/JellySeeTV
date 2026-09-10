import Foundation
import Combine
import AetherEngine

extension PlayerViewModel {

    /// The four ways a live tune can reach the picture, in the same vocabulary the `[LiveDirect] route=`
    /// log line uses. Deliberately not translated: the value only earns its place by matching the log
    /// token a report is correlated against, and a translated one cannot be searched for.
    enum LiveRoute: String, Equatable {
        /// Engine ingest straight from the provider's playlist, Jellyfin out of the data path.
        case direct
        /// Jellyfin remuxes or re-encodes, the engine reads its TranscodingUrl.
        case transcode
        /// A tuner-backed channel read from the buffered stream Jellyfin named in MediaSource.Path,
        /// which skips the second ffmpeg it would otherwise spawn to copy it (#70).
        case tunerFile = "tunerfile"
        /// The static stream route, the pure-copy path a DirectPlay/DirectStream channel needs.
        case staticStream = "static"
    }

    /// Live load: try the tuner's HLS upstream directly first (engine ingest, Jellyfin out of the data path), fall back to the Jellyfin-mediated path once per session. Channels without a TranscodingUrl (tuner hosts, TS/static) go straight to the server path, which picks its own route there (#70). Design: docs/superpowers/specs/2026-06-11-live-hls-ingest-direct-play-design.md.
    func loadLiveStream() async throws {
        // A channel that direct-played before needs nothing from Jellyfin but its upstream URL, and that
        // URL is remembered. Skipping stage-1 drops the two serialized server round trips a zap otherwise
        // pays: AutoOpenLiveStream (Jellyfin connects to the provider itself and ffprobes it) and the
        // awaited tuner close that has to follow it.
        if !didAttemptLiveFallback,
           let memory = directStreamMemory,
           let remembered = memory.upstream(userID: userID, channelID: item.id) {
            let reader = HLSLiveIngestReader(playlistURL: remembered)
            do {
                liveRoute = .direct
                LogTap.shared.note("[LiveDirect] route=direct source=remembered upstream=\(remembered.absoluteString)")
                // No tuner was opened, so there is nothing to release and no transcode to correlate. The
                // synthesized ids exist purely so the Jellyfin session reports still form one session.
                try await startDirectIngest(
                    reader: reader,
                    playSessionID: UUID().uuidString,
                    mediaSourceID: item.id
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A provider can re-point a channel in its m3u without the Jellyfin item id changing. Drop
                // the stale URL and negotiate a fresh one in THIS tune; the once-per-session server
                // fallback is for a freshly negotiated URL failing, not for a stale remembered one.
                usedDirectLivePath = false
                memory.forget(userID: userID, channelID: item.id)
                let detail = reader.terminalError.map { " ingest=\($0)" } ?? ""
                LogTap.shared.note("[LiveDirect] remembered upstream failed, renegotiating: \(error)\(detail)")
            }
        }

        // Stage-1 PlaybackInfo: copy ceiling + the tuner upstream URL (MediaSource.Path) for the direct attempt.
        let info = try await openLiveTuner(maxStreamingBitrate: DirectPlayProfile.liveCopyCeilingBitrate)
        guard let source = info.mediaSources.first else { throw PlayerEngineError.noSource }
        let stageOneTuner = source.liveStreamId

        do {
            // Inside the do block so the catch below releases the stage-1 tuner, same as every other
            // live failure (#70). Logged on every tune, not only on a refusal: a report needs to tell
            // "checked, the audio is fine" apart from "the server named no audio at all" (#100).
            let serverOffersAudioReencode = Self.liveServerOffersAudioReencode(
                transcodeReasons: source.transcodeReasons, transcodingURL: source.transcodingUrl)
            LogTap.shared.note(LiveAudioSupport.logLine(
                for: source.mediaStreams, serverOffersAudioReencode: serverOffersAudioReencode))
            let audioDecision = LiveAudioSupport.decision(
                for: source.mediaStreams, serverOffersAudioReencode: serverOffersAudioReencode)
            if case .refuse(let codec) = audioDecision {
                throw PlayerEngineError.liveAudioUnsupported(codec: codec.displayName)
            }

            // Direct eligibility, decided in liveDirectIngestEligibility: a remux channel whose Path is
            // a real http(s) PROVIDER playlist. Jellyfin's own LiveStreamFiles route is not one, and the
            // guard that used to stand here could not tell them apart (#70).
            let eligibility = Self.liveDirectIngestEligibility(
                transcodingURL: source.transcodingUrl, sourcePath: source.path,
                audioNeedsServerReencode: audioDecision.requiresServerReencode)
            if !didAttemptLiveFallback, case .eligible(let upstream) = eligibility {
                // Reader created here so its terminalError is reachable in the catch fallback log.
                let reader = HLSLiveIngestReader(playlistURL: upstream)
                do {
                    try await loadLiveDirect(info: info, source: source, upstream: upstream, reader: reader)
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Once per session, fall back to the Jellyfin path; the direct attempt already closed (awaited) the stage-1 tuner, so the server path re-negotiates fresh.
                    didAttemptLiveFallback = true
                    usedDirectLivePath = false
                    let detail = reader.terminalError.map { " ingest=\($0)" } ?? ""
                    LogTap.shared.note("[LiveDirect] route=fallback reason=\(error)\(detail)")
                    try await loadLiveStreamViaServer()
                    return
                }
            } else {
                // The route this ends on is named by loadLiveStreamViaServer, which is where it is decided.
                LogTap.shared.note("[LiveDirect] direct ingest not eligible (\(eligibility.logReason))")
            }

            // Ineligible route (static/server): reuse the stage-1 tuner so it isn't leaked and the server path avoids a duplicate roundtrip.
            try await loadLiveStreamViaServer(reusing: (info: info, source: source))
        } catch {
            // The tuner is open from the moment PlaybackInfo answered. If this tune never got far enough
            // to hand it to the session, nothing else will ever close it: Jellyfin's MediaSourceManager
            // releases a live stream only when CloseLiveStream drives its consumer count to zero, or at
            // server shutdown. There is no idle reaper anywhere in that path, so an abandoned zap leaves a
            // tuner ingesting into the transcode folder for as long as the server stays up (#70: three
            // temp files still growing after 9 to 17 hours). Identity-checked, so a load that was
            // superseded cannot close the tuner its successor is already using.
            if let stageOneTuner, activeLiveStreamID != stageOneTuner {
                releaseTuner(stageOneTuner, reason: "tune abandoned before the session owned it")
            }
            throw error
        }
    }

    /// Open the tuner via PlaybackInfo without letting cancellation strand it.
    ///
    /// `AutoOpenLiveStream` opens the tuner as part of answering, and the id that would close it again
    /// exists only in that answer. A request cancelled in flight therefore leaves a tuner open that no
    /// one can name, which is the one leak shape a teardown cannot clean up after the fact. The request
    /// runs in an unstructured task, which does not inherit the caller's cancellation, so the handle
    /// always comes back; if the tune it was for is gone by then, the tuner is released here instead.
    /// A viewer giving up during the seconds Jellyfin spends probing a tuner is the common case on a slow
    /// channel, not a corner (#70).
    private func openLiveTuner(maxStreamingBitrate: Int) async throws -> PlaybackInfoResponse {
        // Never open while one of our own closes is still unanswered: the id Jellyfin closes by names
        // the CHANNEL, not this stream, so an open that overtakes a close either orphans the tuner it
        // replaces or hands that close the stream we are about to play (LiveTunerGate, #70).
        let unsettled = await LiveTunerGate.shared.settle(timeout: 6)
        if unsettled > 0 {
            LogTap.shared.note("[Live] opening with \(unsettled) tuner close(s) still unanswered after 6s")
        }
        let svc = playbackService
        let itemID = item.id
        let user = userID
        let request = Task {
            try await svc.getLivePlaybackInfo(
                itemID: itemID, userID: user,
                profile: DirectPlayProfile.liveProfile(),
                maxStreamingBitrate: maxStreamingBitrate)
        }
        let info = try await request.value
        let source = info.mediaSources.first
        // The open half of the ledger. Without it a capture shows closes with nothing to pair them
        // against, and a tuner we opened and never closed looks exactly like one we never opened (#70).
        if let key = source?.liveStreamId {
            LogTap.shared.note(
                "[Live] tuner opened stream=\(Self.liveLogToken(Self.liveTunerStreamID(fromSourcePath: source?.path)))"
                + " key=\(Self.liveLogToken(key))"
            )
        } else {
            // Not a tuner channel, or an answer that opened nothing. Said out loud because the one thing
            // worse than a tuner we forgot to close is a tuner we were never given a handle for.
            LogTap.shared.note("[Live] PlaybackInfo answered without a live stream id, nothing to close later")
        }
        if Task.isCancelled {
            if let stranded = source?.liveStreamId {
                releaseTuner(stranded, reason: "tune cancelled while the tuner was opening")
            }
            throw CancellationError()
        }
        return info
    }

    /// Close a tuner we opened, without waiting on it and without swallowing the outcome. A close that
    /// quietly fails is a tuner that ingests until the server restarts, and the note is the only trace a
    /// report can carry back (#70).
    ///
    /// "Accepted", not "released", on purpose: `MediaInfoController.CloseLiveStream` answers 204 for
    /// any id, and `MediaSourceManager.CloseLiveStream` does nothing at all when the id is not in
    /// `_openStreams`. The status code says the request was understood, never that a tuner let go.
    /// The key token is what pairs this line with the `tuner opened` line above it.
    @discardableResult
    func releaseTuner(_ liveStreamID: String, reason: String) -> Task<Void, Never> {
        let svc = playbackService
        let token = Self.liveLogToken(liveStreamID)
        return LiveTunerGate.shared.close {
            do {
                try await svc.closeLiveStream(liveStreamID: liveStreamID)
                LogTap.shared.note("[Live] tuner close accepted key=\(token) (\(reason))")
            } catch {
                LogTap.shared.note("[Live] tuner close FAILED key=\(token) (\(reason)): \(error)")
            }
        }
    }

    /// The id Jellyfin names its buffered tuner file after (`LiveStream.UniqueId`, the id in the
    /// `route=tunerfile path=` line and the file name in the server's transcode folder). It is the only
    /// id in a live answer that differs between two opens of the SAME channel; `liveStreamId` does not,
    /// which is the whole reason LiveTunerGate exists.
    static func liveTunerStreamID(fromSourcePath path: String?) -> String? {
        guard let path,
              let relative = JellyfinPlaybackService.liveStreamFileRelativePath(fromSourcePath: path)
        else { return nil }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 4, !parts[3].isEmpty else { return nil }
        return String(parts[3])
    }

    /// Short, pairable form of a live id for the log. Full ids are two or three MD5s long and the HUD
    /// wraps them into unreadability; the tail is enough to pair an open with its close.
    static func liveLogToken(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "none" }
        return id.count <= 8 ? id : "…" + String(id.suffix(8))
    }

    /// Direct play: close the Jellyfin tuner first (single-connection providers must never see two concurrent connections), then hand the upstream playlist to the engine's HLS ingest.
    private func loadLiveDirect(
        info: PlaybackInfoResponse,
        source: PlaybackMediaSource,
        upstream: URL,
        reader: HLSLiveIngestReader
    ) async throws {
        // Stage-1 negotiated this source before the tuner was handed over, so the direct route describes
        // the channel from the same answer the server path would have used.
        activePlaybackSource = source
        if let tuner = source.liveStreamId {
            // Awaited (spec decision 3): single-connection providers must never see the Jellyfin tuner and our direct connection at once, and a straggling close must not race the fallback's freshly opened tuner. Bounded so a hung server can't stall the tune.
            // Started outside the group on purpose: the bound is on how long this tune WAITS, not on the
            // request. Cancelling the close was the same as never sending it, and a tuner nobody closes
            // is one nobody will: Jellyfin has no idle reaper for an open live stream (#70).
            let close = releaseTuner(tuner, reason: "handing the channel to direct ingest")
            enum CloseRace { case closed, timedOut }
            let outcome = await withTaskGroup(of: CloseRace.self) { group -> CloseRace in
                group.addTask {
                    await close.value
                    return .closed
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    return .timedOut
                }
                let first = await group.next() ?? .timedOut
                group.cancelAll()
                return first
            }
            if outcome != .closed {
                // Still running, and it will log its own outcome. Noted here so a report can tell "the
                // close was slow" apart from "the close never happened".
                LogTap.shared.note("[LiveDirect] tuner close still in flight after 3s, proceeding")
            }
        }
        liveRoute = .direct
        LogTap.shared.note("[LiveDirect] route=direct upstream=\(upstream.absoluteString)")
        try await startDirectIngest(
            reader: reader,
            playSessionID: info.playSessionId,
            mediaSourceID: source.id
        )
        // Only a URL that actually played is worth remembering; the next tune of this channel skips
        // stage-1 entirely and goes straight to the ingest above.
        directStreamMemory?.remember(upstream, userID: userID, channelID: item.id)
    }

    /// Hand an upstream playlist to the engine's HLS ingest and wire the live session state around it.
    /// Shared by the negotiated direct path and the remembered-URL shortcut, which differ only in where
    /// the URL and the session ids come from.
    private func startDirectIngest(
        reader: HLSLiveIngestReader,
        playSessionID: String?,
        mediaSourceID: String
    ) async throws {
        self.playSessionID = playSessionID
        self.mediaSourceID = mediaSourceID
        activeLiveStreamID = nil
        usedDirectLivePath = true

        observeLiveEdge()
        try await player.load(
            source: .custom(reader, formatHint: "mpegts"),
            options: LoadOptions(
                suppressDisplayCriteria: false,
                forceDolbyVisionOnNonDVDisplay: preferences.forceDolbyVisionOnNonDVDisplay,
                matchContentEnabled: Self.matchContentEnabled,
                panelIsInHDRMode: Self.panelIsInHDRMode,
                audioBridgeMode: preferences.audioBridgeMode,
                isLive: true,
                dvrWindowSeconds: Self.liveDVRWindowSeconds,
                // Zapping-first join (AetherEngine#195): TARGETDURATION tracks the channel GOP, so
                // short-GOP channels show a picture in ~3-6s instead of 18s+; long-GOP channels
                // quantize back to standard behavior automatically.
                liveJoinProfile: .fastZap,
                preserveASSMarkup: true,
                // Engine picks the preferred-language audio on the first frame (#72), replacing the
                // post-load selectAudioTrack reload that misfired on single-track channels.
                preferredAudioLanguages: effectivePreferredAudioLanguage().map { [$0] } ?? [],
                teletextPage: preferences.liveTeletextPage.page
            ),
            // #64: the viewer's audio pick, named at load. It is the only way onto a track other than
            // the container default here, because the ingest is forward-only and the engine refuses
            // to re-point such a session in place (it logs the refusal).
            audioSourceStreamIndex: pendingLiveAudioStreamIndex.map(Int32.init)
        )

        let engine = player
        scrubPreview.configureLive(enabled: preferences.showScrubPreview) { [weak engine] seconds, maxWidth in
            await engine?.liveScrubThumbnail(atSessionSeconds: seconds, maxWidth: maxWidth)
        }
    }

    /// Jellyfin-mediated live load: open the tuner via PlaybackInfo, pick the infinite live MediaSource, prefer its HLS TranscodingUrl, hand it to the engine with isLive + a DVR window, and set the tuner handle for teardown.
    ///
    /// - Parameter prefetched: reuses a stage-1 PlaybackInfo from the router (avoids a second tuner + duplicate roundtrip); nil triggers a fresh negotiation.
    private func loadLiveStreamViaServer(
        reusing prefetched: (info: PlaybackInfoResponse, source: PlaybackMediaSource)? = nil
    ) async throws {
        // Engine-decode live: request a copy-TS source (liveProfile = Protocol=http, full codec list) and hand to AetherEngine like VOD. The engine demuxes the TS, dispatching h264/hevc to native AVPlayer loopback and MPEG-2/VC-1/MPEG-4 Part 2 to SW, so every codec plays with no re-encode. High copy ceiling (maxStreamingBitrate) keeps the server stream-copying rather than downscaling.
        var info: PlaybackInfoResponse
        var source: PlaybackMediaSource
        if let prefetched {
            info = prefetched.info
            source = prefetched.source
        } else {
            info = try await openLiveTuner(maxStreamingBitrate: DirectPlayProfile.liveCopyCeilingBitrate)
            guard let first = info.mediaSources.first else { throw PlayerEngineError.noSource }
            source = first
        }

        // Two-stage bitrate negotiation: MaxStreamingBitrate is both copy threshold AND encoder target. For a codec NOT in liveProfile's copy list (VideoCodecNotSupported) the high ceiling becomes a 200 Mbps real-time encode target Jellyfin answers with HTTP 500 (device repro: "Infomercial"); re-request at a bounded encode cap, releasing the first probe's tuner.
        if Self.liveNeedsVideoReencode(transcodeReasons: source.transcodeReasons,
                                       transcodingURL: source.transcodingUrl)
            || Self.liveSourceVideoCodecUnknown(source) {
            // Closed BEFORE the second open, not after it. Jellyfin's id names the channel, so the
            // second open would replace this stream's registration and leave it ingesting with a tuner
            // and no handle. The release that used to sit below was guarded on the two ids differing,
            // which only happens when the re-request lands on a different profile of the channel; on a
            // single-profile tuner host the ids match and the guard skipped every release (#70).
            if let staleTuner = source.liveStreamId {
                releaseTuner(staleTuner, reason: "re-negotiating at the re-encode cap")
            }
            info = try await openLiveTuner(maxStreamingBitrate: DirectPlayProfile.liveReencodeCapBitrate)
            guard let rebounded = info.mediaSources.first else { throw PlayerEngineError.noSource }
            source = rebounded
        }

        playSessionID = info.playSessionId
        mediaSourceID = source.id
        activePlaybackSource = source
        activeLiveStreamID = source.liveStreamId

        // Resolve the progressive TS URL the engine's AVIOReader consumes. Three shapes, ranked in
        // chooseLiveServerRoute: a real re-encode has to come from the server, so its TranscodingUrl
        // wins; otherwise the tuner's own buffered stream wins, because a TranscodingUrl that is only a
        // copy-remux is a second ffmpeg copying the very file the tuner route reads (#70); the static
        // route is the fallback whose pure-copy path keeps a DirectPlay/DirectStream channel from
        // black-screening (device repro: "ATV HD", directPlay=1). All three are the same kind of
        // resource to the loader: a growing MPEG-TS with no Content-Length from ProgressiveFileStream.
        let supportsStaticRoute = source.supportsDirectStream == true || source.supportsDirectPlay == true
        let staticURL = supportsStaticRoute ? playbackService.buildStreamURL(
            itemID: item.id,
            mediaSourceID: source.id,
            container: "ts",
            isStatic: true
        ) : nil

        let transcodeURL = source.transcodingUrl.flatMap { playbackService.buildTranscodeURL(relativePath: $0) }
        let tunerFileURL = didAbandonLiveTunerFile
            ? nil
            : source.path.flatMap { playbackService.buildLiveStreamFileURL(sourcePath: $0) }
        // Jellyfin re-encodes only for a codec outside liveProfile's copy list. Everything else it
        // offers a TranscodingUrl for is a stream copy, and that copy's input is the tuner file itself.
        let transcodeIsReencode = Self.liveTranscodeIsRealReencode(
            transcodeReasons: source.transcodeReasons, transcodingURL: source.transcodingUrl)

        let tsURL: URL
        let isTunerFileRoute: Bool
        switch Self.chooseLiveServerRoute(transcodeURL: transcodeURL,
                                          tunerFileURL: tunerFileURL,
                                          staticURL: staticURL,
                                          transcodeIsReencode: transcodeIsReencode) {
        case .transcode(let url):
            tsURL = url
            isTunerFileRoute = false
            liveRoute = .transcode
            // The reasons, not just the verdict: "reencode=true" alone cannot say whether the server
            // is re-encoding the picture or only the soundtrack, and those are different routes home.
            let listed = Self.liveTranscodeReasons(transcodeReasons: source.transcodeReasons,
                                                   transcodingURL: source.transcodingUrl)
                .sorted().joined(separator: ",")
            LogTap.shared.note("[LiveDirect] route=transcode reencode=\(transcodeIsReencode)"
                               + " reasons=\(listed.isEmpty ? "none" : listed)")
        case .tunerFile(let url):
            tsURL = url
            isTunerFileRoute = true
            liveRoute = .tunerFile
            // Path only: the query carries the access token and this line lands in the diagnostic HUD.
            LogTap.shared.note("[LiveDirect] route=tunerfile path=\(url.path)")
        case .staticStream(let url):
            tsURL = url
            isTunerFileRoute = false
            liveRoute = .staticStream
            LogTap.shared.note("[LiveDirect] route=static")
        case nil:
            throw PlayerEngineError.noSource
        }
        usedLiveTunerFilePath = isTunerFileRoute

        observeLiveEdge()

        let options = LoadOptions(
            suppressDisplayCriteria: false,
            forceDolbyVisionOnNonDVDisplay: preferences.forceDolbyVisionOnNonDVDisplay,
            matchContentEnabled: Self.matchContentEnabled,
            panelIsInHDRMode: Self.panelIsInHDRMode,
            audioBridgeMode: preferences.audioBridgeMode,
            isLive: true,
            dvrWindowSeconds: Self.liveDVRWindowSeconds,
            // Zapping-first join (AetherEngine#195), same rationale as the direct path above. A
            // bursty Jellyfin transcode fills the startup cushion at I/O speed either way; the
            // observed-cadence floor keeps bursty ingest patient.
            liveJoinProfile: .fastZap,
            // Raw ASS event lines for the styled-subtitle path (ASSRenderCoordinator); only affects ASS/SSA content.
            preserveASSMarkup: true,
            // Engine picks the preferred-language audio on the first frame (#72), replacing the
            // post-load selectAudioTrack reload that misfired on single-track channels.
            preferredAudioLanguages: effectivePreferredAudioLanguage().map { [$0] } ?? [],
            teletextPage: preferences.liveTeletextPage.page
        )
        // #64: same pick on the server route, where the engine could re-point in place but a
        // re-tune is what the viewer asked for either way. One spelling, one behaviour.
        let liveAudioIndex = pendingLiveAudioStreamIndex.map(Int32.init)

        do {
            try await player.load(url: tsURL, startPosition: nil, options: options,
                                  audioSourceStreamIndex: liveAudioIndex)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Only the tuner-file route can fail for a reason the server routes survive: a proxy that
            // does not forward /LiveTv, or a server whose tuner host fills MediaSource.Path with a
            // route it does not serve. Retreat once per session instead of surfacing, onto the server's
            // own copy of the same stream where there is one and the static route otherwise; the
            // stage-1 tuner is still open, so the retreat reuses it rather than opening a second one.
            guard isTunerFileRoute else { throw error }
            let retreat: (url: URL, route: LiveRoute)
            if let transcodeURL {
                retreat = (transcodeURL, .transcode)
            } else if let staticURL {
                retreat = (staticURL, .staticStream)
            } else {
                throw error
            }
            didAbandonLiveTunerFile = true
            usedLiveTunerFilePath = false
            liveRoute = retreat.route
            // The thrown value alone is often just a type name; the engine's own classification beside it
            // is what says whether the read was refused, timed out or could not be demuxed (#71).
            LogTap.shared.note(
                "[LiveDirect] route=\(retreat.route.rawValue) reason=tunerfile_load_failed(\(error)) "
                + PlayerEngineErrorPresentation.logLine(for: player.errorInfo, engineMessage: "\(error)")
            )
            try await player.load(url: retreat.url, startPosition: nil, options: options,
                                  audioSourceStreamIndex: liveAudioIndex)
        }

        // Live scrub preview frames come from the engine's DVR segment cache (liveScrubThumbnail), not a FrameExtractor (live source is forward-only, FFmpeg has no network). Retune-safe: configureLive resets first.
        let engine = player
        scrubPreview.configureLive(enabled: preferences.showScrubPreview) { [weak engine] seconds, maxWidth in
            await engine?.liveScrubThumbnail(atSessionSeconds: seconds, maxWidth: maxWidth)
        }
    }

    /// Mirror the engine's live-edge publishers into @Observable fields for the DVR transport (no-polling Combine, same as VOD). Single-shot per session via the `hasLiveEdgeObservers` latch; `cancellables` is wiped on teardown/episode-transition, and a live retune re-runs loadLiveStream on the SAME view model.
    func observeLiveEdge() {
        guard !hasLiveEdgeObservers else { return }
        hasLiveEdgeObservers = true
        player.clock.$seekableLiveRange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in self?.liveSeekableRange = range }
            .store(in: &cancellables)
        player.clock.$isAtLiveEdge
            .receive(on: DispatchQueue.main)
            .sink { [weak self] atEdge in self?.isAtLiveEdge = atEdge }
            .store(in: &cancellables)
        player.clock.$behindLiveSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] behind in self?.behindLiveSeconds = behind }
            .store(in: &cancellables)

        // DVR scrubber baseline: map the playhead across the seekable window into `progress` (live duration is 0, so VOD progress math would pin it to 0; the main $currentTime sink skips its progress write for live, making this the sole writer during a live session).
        player.clock.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, self.isLiveSession, !self.isScrubbing else { return }
                guard let range = self.liveSeekableRange else { return }
                // Sodalite#104: the verdict is read from the engine rather than from the mirrored
                // property, because both arrive on separate sinks from the same publish and a
                // one-tick-stale flag would put the snap back for that tick.
                // Sodalite#104 round 4: the anchor is where the KNOB is, on the rail's own span,
                // so a press moves from what the viewer sees. Deliberately not the edge verdict:
                // pinning the anchor would start every rewind at the right stop.
                self.progress = Self.liveRailGeometry(
                    currentTime: time, seekable: range, isAtLiveEdge: false).playhead
            }
            .store(in: &cancellables)
    }

    /// Sodalite#104: where the playhead sits on the DVR rail.
    ///
    /// The rail's right end is the live edge, and the edge is a STEP function: it moves once per
    /// segment cut, by a whole segment. The playhead is continuous. Mapping one onto the other
    /// directly makes the dot reach the end, snap left by segment/span at the next cut, and creep
    /// back, over and over, which is what the device round showed while the badge already said LIVE.
    /// Measured from the published values, 4 s segments on a 10 s window: 1.00, then 0.76, 0.86,
    /// 0.96, 1.00, then 0.84 again.
    ///
    /// So the rail follows the same verdict the badge does. At the edge its right end IS the
    /// playhead, because being within one cut of the newest segment is as close as any client can
    /// get; behind the edge it stays the honest fraction. Both readings now come from one decision
    /// rather than from two quantities that disagree by construction.
    static func liveRailProgress(currentTime: Double,
                                 range: ClosedRange<Double>,
                                 isAtLiveEdge: Bool) -> Float {
        if isAtLiveEdge { return 1 }
        return liveScrubAnchor(currentTime: currentTime, range: range)
    }

    /// Sodalite#104 round 4: the DVR window this session asks the engine to keep, and the span the
    /// rail is drawn across. One constant for both, because a rail whose scale is not the window it
    /// represents is the defect this round exists for.
    static let liveDVRWindowSeconds: Double = 600

    /// Sodalite#104 round 4: where the playhead and the playable region sit on a live rail.
    ///
    /// The rail is a FIXED span of time ending at the live edge. It has to be: the seekable range's
    /// lower bound is the moment the channel was tuned and does not move, while its upper bound
    /// follows the edge, so a position-within-the-range fraction has a numerator and a denominator
    /// that both grow at one second per second and therefore runs to 1 wherever the viewer is.
    /// Measured on a device, a viewer holding thirteen seconds behind live was drawn walking from
    /// 0.271 to 0.552 in ten seconds, and would have reached 0.97 after five minutes without ever
    /// moving. Against a fixed span, ten seconds behind is drawn ten seconds from the right end for
    /// as long as the viewer stays there.
    ///
    /// What the session actually holds is a different question and is answered separately, as the
    /// region of the rail that can be played, so a young session shows a mostly empty rail filling
    /// up rather than a full rail with a moving scale.
    static func liveRailGeometry(currentTime: Double,
                                 seekable: ClosedRange<Double>,
                                 windowSeconds: Double = liveDVRWindowSeconds,
                                 isAtLiveEdge: Bool) -> (playhead: Float, availableFrom: Float) {
        guard windowSeconds > 0 else { return (1, 0) }
        let railStart = seekable.upperBound - windowSeconds
        let fraction = { (t: Double) -> Float in
            Float(max(0, min(1, (t - railStart) / windowSeconds)))
        }
        return (isAtLiveEdge ? 1 : fraction(currentTime), fraction(seekable.lowerBound))
    }

    /// Sodalite#104 round 4: the seconds a scrub position names, on the same span the rail is drawn
    /// across, clamped to what the session can actually play.
    static func liveScrubTarget(scrubProgress: Float,
                                seekable: ClosedRange<Double>,
                                windowSeconds: Double = liveDVRWindowSeconds) -> Double {
        let railStart = seekable.upperBound - windowSeconds
        let target = railStart + Double(scrubProgress) * windowSeconds
        return min(max(target, seekable.lowerBound), seekable.upperBound)
    }

    /// Sodalite#104 round 3: where the playhead really is across the window, as a fraction.
    ///
    /// The DRAWING may pin to the right end at the live edge; the ANCHOR may not. `seekJump` seeds
    /// `scrubProgress` from this, so pinning it would start every rewind at exactly 1.0 and hand the
    /// commit a position the viewer is not at. That is what turned a 10 s press into a return to
    /// live: 1.0 minus 10 s of a 30 minute window is 0.994, which the old snap rule read as "already
    /// live". A rail verdict and a seek anchor are different questions about the same number.
    static func liveScrubAnchor(currentTime: Double, range: ClosedRange<Double>) -> Float {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return Float(max(0, min(1, (currentTime - range.lowerBound) / span)))
    }

    /// Sodalite#104 round 3: has a scrub been pushed to the right STOP, which is the bar's
    /// return-to-live affordance?
    ///
    /// This used to be `>= 0.99`, a fraction of the DVR window standing in for a distance from live.
    /// A window is not a fixed length: 1% of it is 18 s at a 30 minute depth, 6 s at ten minutes and
    /// 1.2 s at two, so the same press meant different things on the same channel depending on how
    /// long it had been playing. The stop is a place on the rail, so it is asked about as one.
    static func liveScrubReachedLiveEdge(scrubProgress: Float) -> Bool { scrubProgress >= 1 }

    /// Sodalite#104: the rail geometry for the session as it stands.
    ///
    /// Both transport bars read this one value. The tvOS round that shipped with the view holding
    /// its own copy of the arithmetic is exactly why it lives here: the copy drifted, and the badge
    /// and the knob then disagreed about the same stepping edge.
    var liveRail: (playhead: Float, availableFrom: Float) {
        guard let range = liveSeekableRange else { return (1, 0) }
        return Self.liveRailGeometry(currentTime: playbackTime, seekable: range,
                                     isAtLiveEdge: isAtLiveEdge)
    }

    /// What a live bar draws the knob at: the in-flight scrub while scrubbing, else the rail.
    var liveDisplayedProgress: Float {
        isScrubbing ? scrubProgress : liveRail.playhead
    }

    /// How far behind the live edge the playhead sits, as a transport label.
    static func liveBehindLabel(seconds: Double) -> String {
        let behind = max(0, Int(seconds))
        return String(format: "-%d:%02d", behind / 60, behind % 60)
    }

    /// The position a live bar prints where a VOD bar prints elapsed time: the word at the edge,
    /// the distance from it otherwise. A live session has no elapsed time worth reading (it would
    /// be seconds since the tune) and no remaining time at all, which is what left the iOS bar
    /// printing -00:00 next to a thirty second rewind.
    var livePositionLabel: String {
        if isAtLiveEdge {
            return NSLocalizedString("livetv.liveBadge", comment: "Live edge label")
        }
        return Self.liveBehindLabel(seconds: behindLiveSeconds)
    }

    /// Snap back to the live edge (return-to-live chip).
    ///
    /// Sodalite#104: the chip supersedes a scrub that has not committed. Without this the rail would
    /// keep drawing a `scrubProgress` the viewer has just overruled, and any pending commit would
    /// seek back out of live a fraction of a second after the return landed.
    func returnToLiveEdge() {
        skipCommitTask?.cancel()
        skipCommitTask = nil
        isScrubbing = false
        scrubPreview.clear()
        pendingSkipBackOrigin = nil
        skipBackBurstOrigin = nil
        Task { await player.seekToLiveEdge() }
    }

    /// Commit a live (DVR) scrub: map `scrubProgress` (0...1) across the
    /// current `liveSeekableRange` and seek, clamped to the window. Scrubbing
    /// fully right (>= 0.99) snaps to the live edge rather than seeking near
    /// it, so the right edge doubles as the return-to-live affordance in v1.
    func commitLiveScrub() {
        guard isScrubbing,
              let range = liveSeekableRange,
              range.upperBound > range.lowerBound else {
            isScrubbing = false
            pendingSkipBackOrigin = nil
            skipBackBurstOrigin = nil
            return
        }
        let p = scrubProgress
        // Mirror VOD commit: set progress before clearing isScrubbing so displayedProgress doesn't flash back to the pre-scrub value before the seek lands.
        progress = p
        isScrubbing = false
        scrubPreview.clear()

        if Self.liveScrubReachedLiveEdge(scrubProgress: p) {
            pendingSkipBackOrigin = nil
            skipBackBurstOrigin = nil
            returnToLiveEdge()
            scheduleControlsHide()
            return
        }

        // Sodalite#104 round 4: across the RAIL's span, which is what the viewer aimed along.
        let target = Self.liveScrubTarget(scrubProgress: p, seekable: range)
        openSkipBackSubtitlesIfNeeded(targetTime: target)
        Task {
            await player.seek(to: target)
            scheduleControlsHide()
        }
        logLiveRailAfterSeek(target: target)
    }

    /// Sodalite#104: what the rail is drawn from, once a second for ten seconds after a live seek.
    ///
    /// The reported shape is a bar that returns to the right a few seconds after a rewind while the
    /// PICTURE stays where the rewind put it. Only three inputs can do that, and the engine's own
    /// verdict line names just one of them, so this prints the reader's side: the playhead the rail
    /// measures, the window it measures against, the verdict, and the fraction that comes out. A
    /// playhead that climbs back to the edge while the picture does not is a clock defect; a
    /// verdict that flips without the playhead moving is a tolerance defect; a fraction that goes to
    /// one with neither is this view model's own arithmetic.
    func logLiveRailAfterSeek(target: Double) {
        liveRailProbe?.cancel()
        liveRailProbe = Task { @MainActor [weak self] in
            for tick in 0...10 {
                guard let self, !Task.isCancelled else { return }
                let range = self.liveSeekableRange
                let drawn = range.map {
                    Self.liveRailProgress(currentTime: self.playbackTime, range: $0,
                                          isAtLiveEdge: self.isAtLiveEdge)
                }
                LogTap.shared.note(
                    "[Live] #104 rail t+\(tick)s: playhead="
                    + String(format: "%.2f", self.playbackTime)
                    + "s target=" + String(format: "%.2f", target)
                    + "s window=" + (range.map {
                        String(format: "%.2f...%.2f", $0.lowerBound, $0.upperBound) } ?? "none")
                    + " behind=" + String(format: "%.2f", self.behindLiveSeconds)
                    + "s atEdge=" + (self.isAtLiveEdge ? "y" : "n")
                    + " scrubbing=" + (self.isScrubbing ? "y" : "n")
                    + " drawn=" + (drawn.map { String(format: "%.3f", $0) } ?? "n/a"))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Feed the scrub preview during a live scrub: map the scrub fraction
    /// across the DVR window to absolute session seconds (the same math
    /// commitLiveScrub uses for the seek).
    func updateLiveScrubPreview() {
        guard let range = liveSeekableRange, range.upperBound > range.lowerBound else { return }
        // Mirror commitLiveScrub, through the same rule and the same span, so the preview matches
        // where the commit lands.
        let p = Self.liveScrubReachedLiveEdge(scrubProgress: scrubProgress)
            ? Float(1) : scrubProgress
        scrubPreview.update(targetSeconds: Self.liveScrubTarget(scrubProgress: p, seekable: range))
    }

    /// Engine `liveSourceReset` entry: a connection drop made the server restart its stream from byte 0 (Jellyfin transcode respawn), so the engine parked. Recovery is full re-negotiation (fresh PlaybackInfo, new PlaySessionId, transcode anchored at live edge, new engine load). Loop-guarded: one retune in flight, minimum spacing, bounded per session.
    func handleLiveSourceReset() {
        guard isLiveSession else {
            LogTap.shared.note("[Live] retune skipped: not a live session")
            return
        }
        // A server the outage watchdog has confirmed dead cannot serve a retune either: it would open a
        // tuner nobody answers and end in the retune-exhausted message, three attempts and a minute later.
        // The outage error is already on screen with its retry.
        guard !serverConfirmedUnreachable else {
            LogTap.shared.note("[Live] retune skipped: server confirmed unreachable")
            hostLoadActive = false
            return
        }
        guard !liveRetuneInFlight else {
            // A second reset rides on the in-flight retune; logged so a STUCK latch (hung loadLiveStream) is visible rather than silently swallowing all future recovery.
            LogTap.shared.note("[Live] retune skipped: already in flight (count=\(liveRetuneCount))")
            return
        }
        let tooSoon = lastLiveRetuneAt.map { Date().timeIntervalSince($0) < 20 } ?? false
        guard liveRetuneCount < 3, !tooSoon else {
            // Every retune fails (server replays from byte 0, or transcode keeps dying); stop cycling tuners and surface. Generalized message since this gate also terminates the mid-session engine-error retune path.
            LogTap.shared.note(
                "[Live] retune EXHAUSTED (count=\(liveRetuneCount) tooSoon=\(tooSoon)); surfacing error"
            )
            hostLoadActive = false
            setEnginePlaybackError(message: String(
                localized: "player.error.liveRetuneExhausted",
                defaultValue: "The live stream keeps failing. Please try the channel again."
            ))
            return
        }
        // A direct-ingest source that died mid-watch is suspect; retune via the Jellyfin path, not the dead upstream. Next manual zap tries direct again (flags reset per startPlayback).
        if usedDirectLivePath {
            didAttemptLiveFallback = true
            usedDirectLivePath = false
            LogTap.shared.note("[LiveDirect] route=fallback reason=mid_session_source_reset")
        } else if usedLiveTunerFilePath {
            // Same logic one route down (#70): the tuner's buffered stream died mid-watch, so retune via
            // Jellyfin's static route, which re-reads that same stream through its own copy-remux.
            didAbandonLiveTunerFile = true
            usedLiveTunerFilePath = false
            LogTap.shared.note("[LiveDirect] route=tunerfile abandoned reason=mid_session_source_reset")
        } else {
            LogTap.shared.note("[Live] retune starting (count=\(liveRetuneCount + 1), already on server route)")
        }

        liveRetuneInFlight = true
        liveRetuneCount += 1
        lastLiveRetuneAt = Date()
        hostLoadActive = true
        Task { [weak self] in
            guard let self else { return }
            await self.retuneLiveStream()
            self.liveRetuneInFlight = false
        }
    }

    /// Live audio switch (#64): re-tune the channel with the picked stream named at load.
    ///
    /// Not a whim of the UI. The engine cannot re-point the audio of a live session on the direct
    /// route, because the ingest reader is forward-only and rebuilding that pipeline would re-consume
    /// a drained FIFO; `selectAudioTrack` refuses it and logs the refusal. Naming the stream at load
    /// works on exactly that kind of source, measured on the CLI, so a switch is a re-join: a few
    /// seconds of black, then the channel back at the live edge on the chosen track.
    ///
    /// The pick outlives this call: every later load of the session, including a recovery retune,
    /// carries it, so a dropped connection cannot quietly put the viewer back on the default track.
    func switchLiveAudioTrack(streamIndex: Int) {
        guard isLiveSession, !liveRetuneInFlight else { return }
        pendingLiveAudioStreamIndex = streamIndex
        // The live subtitle pick re-arms per load; without clearing its latches the $subtitleTracks
        // sink would treat the new session's list as one it has already handled.
        resetLiveSubtitleAutoSelect()
        liveRetuneInFlight = true
        hostLoadActive = true
        LogTap.shared.note("[Live] audio switch: retuning with stream \(streamIndex)")
        Task { [weak self] in
            guard let self else { return }
            await self.retuneLiveStream()
            self.liveRetuneInFlight = false
            self.stateLiveAudioSwitchOutcome(requested: streamIndex)
        }
    }

    /// Say where the switch landed. The engine validates the index against the re-opened container and
    /// falls back to its own pick when it does not name a real track there, which is the right
    /// behaviour and an invisible one: the viewer sees a re-join that ends on the same track and has
    /// nothing to read. A channel whose stream indices move between tunes fails exactly that way.
    private func stateLiveAudioSwitchOutcome(requested: Int) {
        let landed = player.activeAudioTrackIndex
        if landed == requested {
            LogTap.shared.note("[Live] audio switch: now on stream \(requested)")
        } else {
            LogTap.shared.note(
                "[Live] audio switch: asked for stream \(requested), landed on "
                + "\(landed.map(String.init) ?? "none") (tracks=\(player.audioTracks.map { $0.id }))"
            )
        }
    }

    /// Close the dead session, then re-run the live load. Engine `load` supersedes the parked session internally; a CancellationError means a newer load (channel zap) took over mid-retune.
    func retuneLiveStream() async {
        // Close the dead session server-side BEFORE opening the new one: stop report (with tuner handle), explicit transcode kill (orphan ffmpeg writes a growing stream.ts and fills server disk), tuner release.
        let deadTuner = activeLiveStreamID
        let deadSession = playSessionID
        await reportStop(liveStreamID: deadTuner)
        if let deadSession {
            let svc = playbackService
            Task.detached { try? await svc.stopActiveEncodings(playSessionID: deadSession) }
        }
        hasReportedStart = false
        releaseLiveTunerIfNeeded()
        do {
            try await loadLiveStream()
            await reportStart()
        } catch is CancellationError {
            // Superseded by a newer load; nothing to clean up.
        } catch {
            hostLoadActive = false
            setEnginePlaybackError(message: ErrorText.user(for: error))
        }
    }

    /// Release the Jellyfin live tuner if open. Idempotent: clears `activeLiveStreamID` then fires a detached close so a slow server can't stall teardown. No-op for VOD. Belt-and-suspenders against a dropped stop report (which also carries liveStreamId).
    func releaseLiveTunerIfNeeded() {
        guard let liveStreamID = activeLiveStreamID else { return }
        activeLiveStreamID = nil
        releaseTuner(liveStreamID, reason: "session teardown")
    }

    /// Whether the server's probe failed to identify the source's video codec (no streams, or a video stream without a codec). Jellyfin can't stream-copy what it couldn't identify, so the high copy ceiling silently becomes a 200 Mbps ENCODE target (HTTP 500); route through the bounded re-encode cap up front, where ffmpeg's runtime probe may still read it.
    static func liveSourceVideoCodecUnknown(_ source: PlaybackMediaSource) -> Bool {
        guard let video = source.mediaStreams?.first(where: { $0.type == .video })
        else { return true }
        return (video.codec ?? "").isEmpty
    }

    /// Every reason Jellyfin gave for not direct-playing this live source, from BOTH places it puts
    /// them. It populates the MediaSource field unreliably (empty for some channels even when the URL
    /// carries the reason), so neither source alone can be trusted.
    static func liveTranscodeReasons(transcodeReasons: [String]?, transcodingURL: String?) -> Set<String> {
        var reasons = Set(transcodeReasons ?? [])
        if let t = transcodingURL,
           let comps = URLComponents(string: t.hasPrefix("http") ? t : "http://x" + t),
           let query = comps.queryItems?.first(where: { $0.name == "TranscodeReasons" })?.value {
            reasons.formUnion(query.split(separator: ",").map(String.init))
        }
        return reasons
    }

    /// Whether the live source needs a real VIDEO re-encode (codec not in liveProfile's copy list).
    ///
    /// Deliberately video-only, and it must stay that way: its one caller re-negotiates the whole
    /// source at `liveReencodeCapBitrate`, which is a 12 Mbps 1080p H.264 target. An audio-only
    /// mismatch does not turn the copy ceiling into an encode target, so re-negotiating for one would
    /// push a 20 Mbps HEVC broadcast through a 12 Mbps video encode for the sake of its soundtrack.
    static func liveNeedsVideoReencode(transcodeReasons: [String]?, transcodingURL: String?) -> Bool {
        liveTranscodeReasons(transcodeReasons: transcodeReasons, transcodingURL: transcodingURL)
            .contains("VideoCodecNotSupported")
    }

    /// Whether the TranscodingUrl is a real re-encode rather than the stream copy the tuner file
    /// already is, which is the question the route ranking asks (#70).
    ///
    /// Audio counts here even though it does not count for the bitrate re-negotiation above. The
    /// ranking prefers the tuner file because a copy-remux is a second ffmpeg copying the very file
    /// the tuner route reads, and that argument holds only while the answer really is a copy: when
    /// the server is re-encoding audio our own profile says we cannot decode, the raw tuner stream is
    /// the one route that ends in silence. The cost is real and accepted: Jellyfin's remux maps only
    /// `a:0`, so this trades the extra audio PIDs the raw stream carries (#64) for a track that makes
    /// sound, and it is only reached when the server was told we cannot play the original.
    static func liveTranscodeIsRealReencode(transcodeReasons: [String]?, transcodingURL: String?) -> Bool {
        let reasons = liveTranscodeReasons(transcodeReasons: transcodeReasons,
                                           transcodingURL: transcodingURL)
        return reasons.contains("VideoCodecNotSupported") || reasons.contains("AudioCodecNotSupported")
    }

    // MARK: - Route choices, decided in one place so a test can hold them

    /// Whether a live source may go to the engine's HLS ingest, and why not when it may not.
    ///
    /// The ingest reader asks its URL for a playlist. Jellyfin's own `/LiveTv/LiveStreamFiles/` route
    /// answers with a growing MPEG-TS instead, so handing it one fails as `playlistUnreachable` and
    /// costs the tune both the attempt and the fallback before it reaches the server route it was
    /// always going to take. The tuner-backed channel WITH a TranscodingUrl was assumed not to exist;
    /// liveProfile asks Jellyfin for a copy-remux, so the server offers one for nearly every tuner
    /// channel and the old guard let all of them through (#70).
    enum LiveDirectEligibility: Equatable {
        case eligible(URL)
        /// No TranscodingUrl: nothing here is a provider-fed remux channel.
        case notARemuxChannel
        /// Path names Jellyfin's own buffered tuner stream, which is the server route's input, not a playlist.
        case pathIsJellyfinTunerFile
        /// The soundtrack only the server can build. The upstream playlist carries the original,
        /// undecodable audio, so ingesting it directly is the one route that ends in silence (#100).
        case audioNeedsServerReencode
        /// Path is missing, a local file, or otherwise not an http(s) URL.
        case pathNotAnUpstreamURL

        var logReason: String {
            switch self {
            case .eligible: "eligible"
            case .notARemuxChannel: "transcodingUrl=none"
            case .pathIsJellyfinTunerFile: "path=jellyfin_tunerfile"
            case .audioNeedsServerReencode: "audio=needs_server_reencode"
            case .pathNotAnUpstreamURL: "path=not_an_upstream_url"
            }
        }
    }

    /// Whether Jellyfin offered to rebuild this source's AUDIO into something we can play.
    ///
    /// Both halves matter. The reason has to name audio, because a picture-only re-encode copies the
    /// soundtrack through untouched and would leave an AC-4 channel just as silent. And the offer
    /// needs a TranscodingUrl to consume: with a reason but no URL the route ranking has nothing but
    /// the tuner file, which is the original stream (#100).
    static func liveServerOffersAudioReencode(transcodeReasons: [String]?, transcodingURL: String?) -> Bool {
        guard transcodingURL != nil else { return false }
        return liveTranscodeReasons(transcodeReasons: transcodeReasons, transcodingURL: transcodingURL)
            .contains("AudioCodecNotSupported")
    }

    static func liveDirectIngestEligibility(
        transcodingURL: String?, sourcePath: String?, audioNeedsServerReencode: Bool = false
    ) -> LiveDirectEligibility {
        guard transcodingURL != nil else { return .notARemuxChannel }
        // Ahead of the path checks: this one is a statement about the SOUND, and it is the answer a
        // report on such a channel needs to see in the line.
        guard !audioNeedsServerReencode else { return .audioNeedsServerReencode }
        guard let sourcePath else { return .pathNotAnUpstreamURL }
        guard JellyfinPlaybackService.liveStreamFileRelativePath(fromSourcePath: sourcePath) == nil else {
            return .pathIsJellyfinTunerFile
        }
        guard let upstream = URL(string: sourcePath),
              let scheme = upstream.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return .pathNotAnUpstreamURL }
        return .eligible(upstream)
    }

    /// Which server route a live tune takes. Pure, because the decision was previously observable only
    /// by reading a log line off a device, and the ranking is the whole point of #70: a TranscodingUrl
    /// that is only a stream copy loses to the tuner file it would have copied, a real re-encode does not.
    enum LiveServerRouteChoice: Equatable {
        case transcode(URL)
        case tunerFile(URL)
        case staticStream(URL)
    }

    static func chooseLiveServerRoute(
        transcodeURL: URL?,
        tunerFileURL: URL?,
        staticURL: URL?,
        transcodeIsReencode: Bool
    ) -> LiveServerRouteChoice? {
        if let transcodeURL, transcodeIsReencode { return .transcode(transcodeURL) }
        if let tunerFileURL { return .tunerFile(tunerFileURL) }
        if let transcodeURL { return .transcode(transcodeURL) }
        if let staticURL { return .staticStream(staticURL) }
        return nil
    }

}

// MARK: - Following the programme on air

extension PlayerViewModel {

    /// A live session outlives the programme it tuned into. `item` is built from the one that was on
    /// air at tune time, and both the title above the picture and the system Now Playing entry read
    /// `item`, so past a boundary they name a show that has ended while its successor is on screen
    /// (Sodalite#96).
    ///
    /// Same shape as the overview's rows: an answer about "now" carries its own expiry, and here the
    /// expiry is the programme's end. Nothing is polled between two boundaries.
    static let liveProgramMinimumInterval: TimeInterval = 30
    /// No end date to wake on: a channel without EPG, or an answer that never arrived.
    static let liveProgramBlindInterval: TimeInterval = 300

    /// When to look again at what is on air.
    static func nextLiveProgramCheck(after program: JellyfinProgram?, from now: Date) -> Date {
        guard let end = program?.endDate, end > now else {
            return now.addingTimeInterval(liveProgramBlindInterval)
        }
        return max(end, now.addingTimeInterval(liveProgramMinimumInterval))
    }

    func startFollowingLiveProgram() {
        liveProgramFollow?.cancel()
        guard isLiveSession, let channel = liveChannel, let service = liveTvService else { return }
        liveProgramFollow = Task { [weak self] in
            var checkAt = PlayerViewModel.nextLiveProgramCheck(after: self?.liveProgram, from: Date())
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(checkAt.timeIntervalSinceNow, 1)))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let adopted = await self.adoptCurrentLiveProgram(channel: channel, service: service)
                checkAt = PlayerViewModel.nextLiveProgramCheck(after: adopted, from: Date())
            }
        }
    }

    /// Ask the channel what is on air and adopt it. Returns what it found, so the caller schedules
    /// against the answer rather than against what it hoped for: a failed ask reports nothing and
    /// earns the blind interval instead of a retry every thirty seconds.
    private func adoptCurrentLiveProgram(
        channel: JellyfinChannel, service: JellyfinLiveTvServiceProtocol
    ) async -> JellyfinProgram? {
        let now = Date()
        guard let programs = try? await service.getPrograms(
            channelIDs: [channel.id], userID: userID,
            start: now, end: now.addingTimeInterval(PlayerViewModel.liveProgramBlindInterval)),
            let airing = programs.first(where: { $0.isAiring(at: now) })
        else {
            LogTap.shared.note("[LiveProgram] channel=\(channel.id) nothing on air")
            return nil
        }
        guard airing.id != liveProgram?.id else { return airing }
        liveProgram = airing
        // The whole item, not just the name: the description slot carries the programme's overview,
        // and leaving the old one under a new title is the same lie one line down.
        item = JellyfinItem(liveChannel: channel, program: airing)
        stageInitialNowPlayingMetadata()
        LogTap.shared.note("[LiveProgram] now \(airing.name)")
        return airing
    }
}
