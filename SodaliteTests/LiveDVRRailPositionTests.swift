import Testing
import Foundation
@testable import Sodalite

/// Sodalite#104, round 2: the DVR rail's playhead snaps left once per segment.
///
/// The engine half of this issue fixed the LIVE badge, whose verdict is a boolean the engine
/// publishes. The rail is drawn from a different quantity: the playhead's fraction across the
/// seekable range. That range's upper bound is the same stepping edge, so the fraction sawtooths
/// even while the badge says LIVE, which is what the device round still showed.
///
/// Measured on the harness with a DVR window, the host's own formula applied to the published
/// values: the playhead reaches the end of the rail, the next cut moves the upper bound by a whole
/// segment, and the fraction drops by segment/span before creeping back up.
///
///     cur=8.02  range 1.42...7.42   -> 1.00
///     cur=9.02  range 1.42...11.42  -> 0.76     the snap
///     cur=10.02 range 1.42...11.42  -> 0.86
///     cur=11.02 range 1.42...11.42  -> 0.96
///     cur=12.12 range 1.42...11.42  -> 1.00
///     cur=13.12 range 1.42...15.42  -> 0.84     and again
///
/// The rail now follows the same verdict the badge does: at the live edge its right end IS the
/// playhead, because being within one cut of the newest segment is as close as a client can be.
/// Behind the edge it stays the honest fraction.
@Suite("The DVR rail follows the live verdict (Sodalite#104)")
struct LiveDVRRailPositionTests {

    @Test("at the live edge the playhead sits at the end of the rail")
    func atEdgePinsToTheEnd() {
        // The three ticks the harness printed while the badge said LIVE, one per segment phase.
        #expect(PlayerViewModel.liveRailProgress(
            currentTime: 9.02, range: 1.42...11.42, isAtLiveEdge: true) == 1)
        #expect(PlayerViewModel.liveRailProgress(
            currentTime: 10.02, range: 1.42...11.42, isAtLiveEdge: true) == 1)
        #expect(PlayerViewModel.liveRailProgress(
            currentTime: 12.12, range: 1.42...11.42, isAtLiveEdge: true) == 1)
    }

    @Test("the sawtooth the device showed is gone across a whole cut")
    func noSnapAcrossACut() {
        let ticks: [(Double, ClosedRange<Double>)] = [
            (8.02, 1.42...7.42), (9.02, 1.42...11.42), (10.02, 1.42...11.42),
            (11.02, 1.42...11.42), (12.12, 1.42...11.42), (13.12, 1.42...15.42),
        ]
        let values = ticks.map {
            PlayerViewModel.liveRailProgress(currentTime: $0.0, range: $0.1, isAtLiveEdge: true)
        }
        #expect(values.allSatisfy { $0 == 1 })
    }

    @Test("behind the edge the rail is the honest fraction")
    func behindTheEdgeMapsTheFraction() {
        // 30 s back in a 120 s window: three quarters along, and it stays there.
        let p = PlayerViewModel.liveRailProgress(
            currentTime: 90, range: 0...120, isAtLiveEdge: false)
        #expect(abs(p - 0.75) < 0.001)
    }

    @Test("a playhead past the published edge still lands at the end")
    func aPlayheadPastTheEdgeClamps() {
        // The edge lags the playhead by up to a tick between cuts, which is how the rail used to
        // reach 1.0 in the first place. Clamped either way, so the dot never leaves the rail.
        #expect(PlayerViewModel.liveRailProgress(
            currentTime: 8.02, range: 1.42...7.42, isAtLiveEdge: false) == 1)
        #expect(PlayerViewModel.liveRailProgress(
            currentTime: 0.5, range: 1.42...7.42, isAtLiveEdge: false) == 0)
    }

    @Test("a degenerate range reports the start rather than dividing by zero")
    func aDegenerateRangeIsSafe() {
        #expect(PlayerViewModel.liveRailProgress(
            currentTime: 5, range: 5...5, isAtLiveEdge: false) == 0)
        // At the edge the verdict still wins: a window with no span is a live-only session.
        #expect(PlayerViewModel.liveRailProgress(
            currentTime: 5, range: 5...5, isAtLiveEdge: true) == 1)
    }
}
