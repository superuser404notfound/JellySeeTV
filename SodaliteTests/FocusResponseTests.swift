import Testing
import SwiftUI
@testable import Sodalite

/// `FocusResponse` is the motion half of the focus gesture (Sodalite#130). Before it existed the
/// scale, the shadow and the settle time were re-typed at 46 sites and drifted into nine scale
/// values and four durations, so what is pinned here is all three parts of the fix: the value each
/// role carries, the ORDER the scales stand in, and the displacement those scales actually produce.
///
/// The order and the displacement are the parts a retune can break silently. A role edited on its
/// own still compiles and still looks deliberate on the screen it was edited for; what it breaks is
/// the relationship to its neighbours, and nobody sees that until they point a remote at a TV.
struct FocusResponseTests {

    // MARK: values

    @Test("every role keeps the scale it was pinned at")
    func scales() {
        #expect(FocusResponse.card.scale == 1.05)
        #expect(FocusResponse.tile.scale == 1.03)
        #expect(FocusResponse.row.scale == 1.015)
        #expect(FocusResponse.inline.scale == 1.02)
        #expect(FocusResponse.chip.scale == 1.05)
        #expect(FocusResponse.pill.scale == 1.08)
    }

    @Test("every role keeps the shadow it was pinned at, and the two flat roles stay flat")
    func shadows() {
        #expect(FocusResponse.card.shadow == .init(opacity: 0.4, radius: 20, y: 10))
        #expect(FocusResponse.tile.shadow == .init(opacity: 0.3, radius: 15, y: 8))
        #expect(FocusResponse.row.shadow == .init(opacity: 0.3, radius: 14, y: 6))
        #expect(FocusResponse.pill.shadow == .init(opacity: 0.3, radius: 10, y: 5))
        // A row inside a box and a small control have no ground of their own to lift off.
        #expect(FocusResponse.inline.shadow == nil)
        #expect(FocusResponse.chip.shadow == nil)
    }

    @Test("one settle time app-wide, and the player pill is the only documented exception")
    func settle() {
        #expect(FocusResponse.settle == .easeInOut(duration: 0.15))
        for response in [FocusResponse.card, .tile, .row, .inline, .chip] {
            #expect(response.animation == FocusResponse.settle)
        }
        // Forced by the transport row's transaction so siblings interpolate together, not a retune.
        #expect(FocusResponse.pill.animation == .smooth(duration: 0.32))
    }

    /// `MediaFocusRing` reads this rather than its old `.easeInOut(duration: 0.2)` literal. The ring
    /// and the lift are two halves of one gesture, and they used to settle at different speeds on
    /// the same element: every cast portrait and every Seerr episode still wore a 0.2 ring over a
    /// 0.15 lift. Nothing in a View can assert that coupling, so the shared value is asserted here.
    @Test("the ring's settle is the card's settle")
    func ringSharesTheCardSettle() {
        #expect(FocusResponse.card.animation == FocusResponse.settle)
    }

    // MARK: order

    /// The scales are NOT interchangeable numbers and must not be sorted by taste. They fall in the
    /// inverse order of how wide the element they belong to is, because what a viewer reads across
    /// the room is the displacement in points, not the ratio. Sorting them any other way makes a
    /// wide row jump further than a poster.
    @Test("the scales stand in the inverse order of their elements' width")
    func scaleOrder() {
        #expect(FocusResponse.pill.scale > FocusResponse.chip.scale)   // ~80pt  over ~140pt
        #expect(FocusResponse.chip.scale >= FocusResponse.card.scale)  // ~140pt over 220pt
        #expect(FocusResponse.card.scale > FocusResponse.tile.scale)   // 220pt  over ~600pt
        #expect(FocusResponse.tile.scale > FocusResponse.inline.scale) // ~600pt over ~800pt
        #expect(FocusResponse.inline.scale > FocusResponse.row.scale)  // ~800pt over ~1000pt
    }

    @Test("a focus lift never shrinks the control it marks")
    func everyRoleLifts() {
        for response in [FocusResponse.card, .tile, .row, .inline, .chip, .pill] {
            #expect(response.scale > 1.0)
        }
    }

    // MARK: displacement

    /// The reason the scales differ at all. Against the real tvOS card metrics, `.card` moves every
    /// piece of artwork it owns by a comparable number of POINTS, which is the thing that reads as
    /// "this one is focused" from ten feet. A scale that looks like an outlier next to its
    /// neighbours in a diff is usually a different-sized element, and this is the check that says so.
    @Test("the card role moves every artwork it owns by a comparable distance")
    func cardDisplacement() {
        let metrics = LayoutMetrics.tv
        let widths: [(String, CGFloat)] = [
            ("poster", metrics.posterSize.width),
            ("landscape", metrics.landscapeSize.width),
            ("profile", metrics.profileCardSize.width),
            ("cast portrait", metrics.castPortrait),
        ]
        for (name, width) in widths {
            let perSide = width * (FocusResponse.card.scale - 1) / 2
            #expect(perSide >= 4 && perSide <= 10,
                    "\(name) lifts by \(perSide)pt per side, outside the 4-10pt the role is tuned for")
        }
    }

    // MARK: derivations

    @Test("flat keeps the lift and the settle and drops only the shadow")
    func flatDropsOnlyTheShadow() {
        let flat = FocusResponse.card.flat
        #expect(flat.shadow == nil)
        #expect(flat.scale == FocusResponse.card.scale)
        #expect(flat.animation == FocusResponse.card.animation)
    }

    @Test("withShadow replaces the shadow and keeps the lift and the settle")
    func withShadowKeepsTheRest() {
        let tuned = FocusResponse.card.withShadow(opacity: 0.3, radius: 10, y: 5)
        #expect(tuned.shadow == .init(opacity: 0.3, radius: 10, y: 5))
        #expect(tuned.scale == FocusResponse.card.scale)
        #expect(tuned.animation == FocusResponse.card.animation)
    }
}
