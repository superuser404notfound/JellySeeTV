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
