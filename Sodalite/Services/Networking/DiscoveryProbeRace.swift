import Foundation

/// Probes server-discovery candidates concurrently instead of one after another.
///
/// A bare address expands into up to four scheme/port candidates and at most one of them can be
/// right. The wrong ones either refuse instantly (nothing listening) or hang until the request
/// times out, which is what a home router does from the outside: it DROPs the SYN rather than
/// refusing it. Measured on macOS 26 against a blackholed RFC1918 host, one such candidate costs
/// **61.0 s** with URLSession's default request timeout, so the old sequential loop could sit on a
/// spinner for minutes before reaching the candidate that works (Sodalite#82).
///
/// Two bounds replace that: every candidate carries its own cap, and all of them start at once.
/// Order still decides the winner, so https is never traded for http just because http answered
/// first; `grace` only caps how long a still-pending higher-priority candidate may hold up a
/// lower-priority one that already succeeded.
///
/// The parallel start does mean the plain-http candidates now go out even when https works. They
/// carry no credentials (both backends expose an unauthenticated status endpoint) and they can
/// never win a race a higher-priority candidate also finishes.
nonisolated enum DiscoveryProbeRace {
    /// Per-candidate ceiling once the race has heard from anybody: far above a healthy status round
    /// trip on slow cellular, far below the 61 s a dropped SYN costs by default.
    static let candidateTimeout: Duration = .seconds(10)

    /// Ceiling for a race in which NOTHING has answered by `candidateTimeout`. Capping a silent
    /// candidate is a verdict about the address; a race where not one candidate has spoken has no
    /// evidence for that verdict and may simply be sitting behind a link the app itself is busy
    /// saturating, so the silent candidates get this window instead (Sodalite#82, round 2).
    static let extendedCandidateTimeout: Duration = .seconds(25)

    /// How long a pending higher-priority candidate may delay an already-successful one.
    static let priorityGrace: Duration = .seconds(2)

    /// Runs every candidate at once and returns their verdicts in candidate order, so the caller
    /// keeps picking the first success exactly as a sequential loop would. A `nil` entry marks a
    /// candidate that was still in flight when the race ended, which only happens once a
    /// higher-priority winner is already settled.
    static func run<Success: Sendable>(
        candidates: [URL],
        timeout: Duration = candidateTimeout,
        extendedTimeout: Duration = extendedCandidateTimeout,
        grace: Duration = priorityGrace,
        probe: @escaping @Sendable (URL) async -> Result<Success, APIError>
    ) async -> [Result<Success, APIError>?] {
        guard !candidates.isEmpty else { return [] }

        let answered = AnswerSignal()

        return await withTaskGroup(of: ProbeEvent<Success>.self) { group in
            for (index, url) in candidates.enumerated() {
                group.addTask {
                    .verdict(index, await bounded(
                        url,
                        timeout: timeout,
                        extendedTimeout: extendedTimeout,
                        answered: answered,
                        probe: probe
                    ))
                }
            }

            var verdicts = [Result<Success, APIError>?](repeating: nil, count: candidates.count)
            var winner: Int?
            var graceRunning = false

            while let event = await group.next() {
                switch event {
                case .graceExpired:
                    // Whatever still outranks the winner has had its window; stop waiting on it.
                    group.cancelAll()
                    return verdicts

                case .verdict(let index, let result):
                    verdicts[index] = result
                    if case .success = result, winner.map({ index < $0 }) ?? true {
                        winner = index
                    }
                    guard let leader = winner else { continue }
                    // Every candidate ahead of the winner has answered, so nothing better can land.
                    if verdicts[..<leader].allSatisfy({ $0 != nil }) {
                        group.cancelAll()
                        return verdicts
                    }
                    if !graceRunning {
                        graceRunning = true
                        group.addTask {
                            try? await Task.sleep(for: grace)
                            return .graceExpired
                        }
                    }
                }
            }

            return verdicts
        }
    }

    /// One candidate, capped. The cap lives here rather than on the shared `HTTPClient` session
    /// because it is discovery-specific: a probe against a guessed address is allowed to be
    /// declared dead long before a real API call would be.
    private static func bounded<Success: Sendable>(
        _ url: URL,
        timeout: Duration,
        extendedTimeout: Duration,
        answered: AnswerSignal,
        probe: @escaping @Sendable (URL) async -> Result<Success, APIError>
    ) async -> Result<Success, APIError> {
        await withTaskGroup(of: Result<Success, APIError>?.self) { group in
            group.addTask {
                let result = await probe(url)
                // A probe that returns because it was cancelled has not answered anything; only a
                // verdict this candidate reached on its own counts as evidence for the others.
                if !Task.isCancelled { answered.mark() }
                return result
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return nil }
                if !answered.hasAnswer, extendedTimeout > timeout {
                    try? await Task.sleep(for: extendedTimeout - timeout)
                }
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure(.timeout)
        }
    }

    /// Everything a probe can throw, folded into the vocabulary the candidate loop classifies by.
    /// A cancelled probe (caller left the screen, or a settled winner ended the race) must not be
    /// mistaken for a protocol answer, so it lands on `.serverUnreachable` like a dead host.
    static func normalized(_ error: any Error) -> APIError {
        switch error {
        case is CancellationError:
            return .serverUnreachable
        case let error as DecodingError:
            return .decodingError(error)
        case let error as APIError:
            return error
        default:
            return .networkError(error)
        }
    }

    /// One candidate attempt plus the diagnostic line that goes with it.
    ///
    /// The line is written here rather than in the caller's `catch` because a probe ending in a
    /// `CancellationError` has nothing to say about the address: the race cancelled it, either
    /// because its cap expired or because a higher-priority candidate had already won. Round 1 of
    /// Sodalite#82 printed "unreachable" for exactly that case, which reads as a verdict about the
    /// server, and sent the reporter looking for a network fault that was not there. Those two
    /// fates are printed by `logUnanswered` afterwards, where they can be told apart.
    static func attempt<Success: Sendable>(
        label: String,
        url: URL,
        describe: @Sendable (Success) -> String,
        body: @Sendable () async throws -> Success
    ) async -> Result<Success, APIError> {
        let start = ContinuousClock.now
        do {
            let value = try await body()
            LogTap.shared.note("[discovery] \(label) \(url.absoluteString) -> \(describe(value)) in \(elapsedText(since: start))")
            return .success(value)
        } catch is CancellationError {
            return .failure(.serverUnreachable)
        } catch {
            let mapped = normalized(error)
            LogTap.shared.note("[discovery] \(label) \(url.absoluteString) -> \(logLabel(for: mapped)) in \(elapsedText(since: start))")
            return .failure(mapped)
        }
    }

    /// Prints the candidates that never produced an answer of their own, once the race has ended and
    /// their fate is known: `.timeout` is our cap firing, `nil` is a candidate abandoned because a
    /// higher-priority one had already won. Both end when the race ends, so both carry its elapsed.
    static func logUnanswered<Success: Sendable>(
        label: String,
        candidates: [URL],
        verdicts: [Result<Success, APIError>?],
        since start: ContinuousClock.Instant
    ) {
        let elapsed = elapsedText(since: start)
        for (index, verdict) in verdicts.enumerated() where index < candidates.count {
            let address = candidates[index].absoluteString
            switch verdict {
            case .failure(.timeout):
                LogTap.shared.note("[discovery] \(label) \(address) -> silent, cancelled at the cap after \(elapsed)")
            case .none:
                LogTap.shared.note("[discovery] \(label) \(address) -> silent, abandoned after \(elapsed) (another candidate answered)")
            default:
                continue
            }
        }
    }

    /// The single error a whole race of failed candidates collapses to.
    ///
    /// A candidate that connected but did not speak the protocol (captive portal, wrong service)
    /// describes the address better than any transport verdict, so it wins. Below that, a candidate
    /// this race cancelled at its own cap surfaces as `.timeout` and NOT as `.serverUnreachable`:
    /// the cap is our decision to stop waiting, and printing it as a statement about the server is
    /// what sent the Sodalite#82 reporter looking for a network fault that was not there.
    static func aggregateError<Success: Sendable>(_ verdicts: [Result<Success, APIError>?]) -> APIError {
        // A denied Local Network permission outranks every verdict about the address, because it is
        // not one: it says this device would not have let ANY of these candidates through, so the
        // captive-portal and cap readings below describe a race that never got to happen.
        for verdict in verdicts {
            if case .failure(.localNetworkDenied) = verdict { return .localNetworkDenied }
        }
        // Next, and above the protocol group below, a refused certificate: it is the only verdict in
        // this set whose resolution is a decision the user can make, and it comes from a candidate
        // that is plainly answering. Measured against a real server on 2026-09-07: nginx in front of
        // Jellyfin answers the http probe on the https port with `400 The plain HTTP request was
        // sent to HTTPS port`, which is a true statement about a candidate nobody can act on, and
        // ranked below it the whole race read as "Server unreachable" while the trust sheet, whose
        // entire job is to ask about exactly this, never appeared.
        for verdict in verdicts {
            if case .failure(.certificateUntrusted(let host, let fingerprint)) = verdict {
                return .certificateUntrusted(host: host, fingerprint: fingerprint)
            }
        }
        var sawTimeout = false
        for verdict in verdicts {
            guard case .failure(let error) = verdict else { continue }
            switch error {
            case .decodingError, .httpError, .invalidResponse, .unauthorized:
                return error
            case .timeout:
                sawTimeout = true
            default:
                continue
            }
        }
        return sawTimeout ? .timeout : .serverUnreachable
    }

    /// Short outcome word for a diagnostic line. Deliberately not `errorDescription`: that one is
    /// localized user copy, and a log line a reporter pastes into an issue has to read the same in
    /// every language.
    static func logLabel(for error: APIError) -> String {
        switch error {
        case .httpError(let statusCode, _): "HTTP \(statusCode)"
        case .unauthorized: "HTTP 401"
        case .decodingError: "wrong service"
        case .timeout: "timed out"
        case .serverUnreachable: "unreachable"
        case .localNetworkDenied: "local network denied"
        case .certificateUntrusted(let host, _): "certificate refused (\(host))"
        case .invalidResponse: "invalid response"
        case .invalidURL: "invalid URL"
        case .networkError(let underlying): "network error (\((underlying as NSError).code))"
        }
    }

    /// "1.4s" since `start`, for the diagnostic lines both discovery services emit.
    static func elapsedText(since start: ContinuousClock.Instant) -> String {
        let components = start.duration(to: .now).components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return String(format: "%.1fs", seconds)
    }
}

/// Set the moment any candidate in a race produces an answer of its own: a success, an HTTP status,
/// a refused connection, a failed name lookup. Read by the soft cap, which is a verdict about a
/// silent candidate and needs at least one candidate to have spoken before it can draw one.
private nonisolated final class AnswerSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var answered = false

    var hasAnswer: Bool {
        lock.lock()
        defer { lock.unlock() }
        return answered
    }

    func mark() {
        lock.lock()
        answered = true
        lock.unlock()
    }
}

private nonisolated enum ProbeEvent<Success: Sendable>: Sendable {
    case verdict(Int, Result<Success, APIError>)
    case graceExpired
}
