import Testing
import Foundation
@testable import Sodalite

/// Sodalite#104, round 4: the DVR rail marched to the right end while the viewer stayed put.
///
/// Captured on a device, one line per second after a rewind, with the numbers the rail was drawn
/// from. The playhead stays 11 to 16 s behind the live edge for the whole run, so the viewer has not
/// moved relative to live at all, and the knob still walks across half the rail in ten seconds:
///
///     t+1s   playhead=33235.72  window=33230.02...33251.02  drawn=0.271
///     t+5s   playhead=33239.82  window=33230.02...33251.02  drawn=0.467
///     t+6s   playhead=33240.82  window=33230.02...33257.02  drawn=0.400
///     t+10s  playhead=33244.92  window=33230.02...33257.02  drawn=0.552
///
/// The window's LOWER bound is the moment the channel was tuned and never moves; its upper bound
/// follows the live edge. Both the numerator and the denominator of a position-within-the-window
/// fraction therefore grow at one second per second, so the fraction runs to 1 no matter where the
/// viewer is. Five minutes in, a viewer ten seconds behind live is drawn at 0.97.
///
/// A DVR rail is a fixed span of time ending at the live edge, the way a broadcast timeline reads:
/// right is now, left is a constant distance before it. Then a ten second rewind is drawn ten
/// seconds from the right end for as long as the viewer stays there. What the session actually
/// holds is a second question, drawn as the available region rather than as the scale.
@Suite("The DVR rail is a fixed span ending at the live edge (Sodalite#104)")
struct LiveRailGeometryTests {

    private let span = PlayerViewModel.liveDVRWindowSeconds

    /// The device capture, replayed: the edge and the playhead both advance, the resident floor
    /// stays at the tune, and `behind` holds around thirteen seconds.
    @Test("a viewer who does not move is not drawn moving")
    func aStationaryViewerStaysPut() {
        let floor = 33230.02
        let samples: [(playhead: Double, edge: Double)] = [
            (33235.72, 33251.02), (33236.72, 33251.02), (33237.72, 33251.02),
            (33238.82, 33251.02), (33239.82, 33251.02), (33240.82, 33257.02),
            (33241.82, 33257.02), (33242.92, 33257.02), (33243.92, 33257.02),
            (33244.92, 33257.02),
        ]
        let drawn = samples.map {
            PlayerViewModel.liveRailGeometry(
                currentTime: $0.playhead, seekable: floor...$0.edge,
                windowSeconds: span, isAtLiveEdge: false).playhead
        }
        // Every sample sits its own distance behind the edge, and that distance is what is drawn.
        for (sample, value) in zip(samples, drawn) {
            let behind = sample.edge - sample.playhead
            #expect(abs(Double(value) - (1 - behind / span)) < 0.001)
        }
        // The old model walked 0.271 -> 0.552 across these ten seconds. The spread is now the
        // sawtooth of the edge itself, a couple of percent, not half the rail.
        let spread = Double(drawn.max()! - drawn.min()!)
        #expect(spread < 0.02)
    }

    @Test("the same rewind reads the same however long the channel has been on")
    func aRewindDoesNotDriftWithSessionAge() {
        // Ten seconds behind, twenty seconds into the session and five minutes into it.
        let young = PlayerViewModel.liveRailGeometry(
            currentTime: 990, seekable: 985...1000, windowSeconds: span, isAtLiveEdge: false)
        let old = PlayerViewModel.liveRailGeometry(
            currentTime: 1290, seekable: 985...1300, windowSeconds: span, isAtLiveEdge: false)
        #expect(abs(young.playhead - old.playhead) < 0.001)
        #expect(abs(Double(young.playhead) - (1 - 10.0 / span)) < 0.001)
    }

    @Test("what the session holds is the available region, not the scale")
    func theResidentPartIsDrawnSeparately() {
        // Twenty seconds after the tune: the rail is still ten minutes wide, and only the last
        // fifteen seconds of it can be played.
        let g = PlayerViewModel.liveRailGeometry(
            currentTime: 1000, seekable: 985...1000, windowSeconds: span, isAtLiveEdge: true)
        #expect(abs(Double(g.availableFrom) - (1 - 15.0 / span)) < 0.001)
        #expect(g.playhead == 1)
        // Once the session outlives the window, everything on the rail is available.
        let mature = PlayerViewModel.liveRailGeometry(
            currentTime: 4000, seekable: 3400...4000, windowSeconds: span, isAtLiveEdge: true)
        #expect(mature.availableFrom == 0)
    }

    @Test("a rewind past what is held is clamped onto the rail, not off it")
    func aPositionBelowTheWindowClamps() {
        let g = PlayerViewModel.liveRailGeometry(
            currentTime: 100, seekable: 985...1000, windowSeconds: span, isAtLiveEdge: false)
        #expect(g.playhead == 0)
    }

    @Test("a scrub maps across the rail, so pressing and drawing agree")
    func scrubTargetsUseTheSameSpan() {
        // The rail's own arithmetic, inverted: 10 s before the edge is where a 10 s press lands.
        let target = PlayerViewModel.liveScrubTarget(
            scrubProgress: Float(1 - 10.0 / span), seekable: 985...1000, windowSeconds: span)
        #expect(abs(target - 990) < 0.001)
        // And it never lands outside what the session holds.
        let clamped = PlayerViewModel.liveScrubTarget(
            scrubProgress: 0, seekable: 985...1000, windowSeconds: span)
        #expect(clamped == 985)
    }
}

/// Sodalite#104 rounds 2 and 3, the two findings that survived into the fixed-span rail.
///
/// Round 2: the live edge is a STEP function. It moves once per segment cut, by a whole segment,
/// while the playhead is continuous, so a rail that measured the playhead against it reached the end,
/// snapped left by one segment at the next cut and crept back, over and over, while the badge already
/// said LIVE. Measured from the published values, 4 s segments on a 10 s window: 1.00, then 0.76,
/// 0.86, 0.96, 1.00, then 0.84 again. The rail therefore follows the same verdict the badge does.
///
/// Round 3: pushing the knob to the right STOP is the bar's return-to-live affordance, and the rule
/// that reads it has to be a place on the rail. It used to be `>= 0.99`, a fraction of the DVR window
/// standing in for a distance from live, which is 18 s at a 30 minute depth, 6 s at ten minutes and
/// 1.2 s at two: the same press meant different things on the same channel depending on how long it
/// had been playing, and on a deep window it swallowed a ten second rewind whole.
@Suite("The rail follows the live verdict, and the stop is a place (Sodalite#104)")
struct LiveRailVerdictTests {

    private let span = PlayerViewModel.liveDVRWindowSeconds

    @Test("at the live edge the playhead sits at the end of the rail")
    func atEdgePinsToTheEnd() {
        // The ticks the harness printed across a whole cut while the badge said LIVE. The window's
        // upper bound steps by a segment in the middle of them; none of that reaches the knob.
        let ticks: [(Double, ClosedRange<Double>)] = [
            (8.02, 1.42...7.42), (9.02, 1.42...11.42), (10.02, 1.42...11.42),
            (11.02, 1.42...11.42), (12.12, 1.42...11.42), (13.12, 1.42...15.42),
        ]
        for (playhead, window) in ticks {
            #expect(PlayerViewModel.liveRailGeometry(
                currentTime: playhead, seekable: window,
                windowSeconds: span, isAtLiveEdge: true).playhead == 1)
        }
    }

    @Test("a degenerate window is safe rather than a division by zero")
    func aDegenerateWindowIsSafe() {
        #expect(PlayerViewModel.liveRailGeometry(
            currentTime: 5, seekable: 5...5, windowSeconds: span, isAtLiveEdge: true).playhead == 1)
        #expect(PlayerViewModel.liveRailGeometry(
            currentTime: 5, seekable: 5...5, windowSeconds: 0, isAtLiveEdge: false).playhead == 1)
    }

    @Test("pushing the knob to the right stop is the return-to-live affordance")
    func theRightStopSnaps() {
        #expect(PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: 1))
        // scrubProgress is clamped to 0...1 at every writer, so the stop is exact.
        #expect(PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: 1.0001))
        #expect(!PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: 0.995))
    }

    @Test("a ten second rewind is a rewind, whatever the DVR depth")
    func aShortRewindIsARewind() {
        // What the old 1% rule swallowed: on the fixed span a press is the same distance every time,
        // and it is nowhere near the stop.
        let afterOnePress = Float(1 - 10.0 / span)
        #expect(!PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: afterOnePress))
        #expect(afterOnePress > 0.98)
    }
}

/// Sodalite#104: the iOS bar printed `-00:00` next to a thirty second rewind, because it was
/// reading a VOD remaining time on a session that has no duration. A live transport prints the
/// distance from the live edge instead, and both platforms format it here.
@Suite("A live transport prints a distance from live (Sodalite#104)")
struct LiveTransportLabelTests {

    @Test("a rewind reads as the offset it moved")
    func aRewindReadsAsItsOffset() {
        #expect(PlayerViewModel.liveBehindLabel(seconds: 30) == "-0:30")
        #expect(PlayerViewModel.liveBehindLabel(seconds: 95) == "-1:35")
        #expect(PlayerViewModel.liveBehindLabel(seconds: PlayerViewModel.liveDVRWindowSeconds) == "-10:00")
    }

    @Test("the edge itself is not drawn as a negative offset")
    func theEdgeIsNotNegative() {
        #expect(PlayerViewModel.liveBehindLabel(seconds: 0) == "-0:00")
        // The engine's behind-live figure can cross zero by a fraction between two cuts.
        #expect(PlayerViewModel.liveBehindLabel(seconds: -2) == "-0:00")
    }
}
