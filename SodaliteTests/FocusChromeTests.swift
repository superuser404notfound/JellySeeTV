import Testing
import SwiftUI
@testable import Sodalite

/// The two strokes that mark focus (Sodalite#134). `MediaFocusRing` is drawn OUTSIDE the artwork it
/// marks, `focusStroke` on a panel's own edge, and the geometry rule that keeps the first concentric
/// is the thing five call sites got wrong while two got it right. It is pinned here because nothing
/// about a wrong radius fails to compile, and on screen it is a dark crescent in a corner that reads
/// as an artwork artifact rather than as a bug in the chrome.
struct FocusChromeTests {

    @Test("the ring derives a radius concentric with the content it marks")
    func ringIsConcentricWithItsContent() {
        // A rounded rectangle offset outward by d has radius r + d. The ring is padded out by its
        // own width, so a 12pt card needs a 16pt ring for the stroke's inner edge to land on the
        // card's corner. Reusing the content's radius is what pinched five sites.
        for contentRadius in [CGFloat(8), 10, 12, 14, 16, 20] {
            let ring = MediaFocusRing(cornerRadius: contentRadius, isFocused: true)
            #expect(ring.shape.cornerSize.width == contentRadius + MediaFocusRing<RoundedRectangle>.outset)
            #expect(ring.shape.cornerSize.height == contentRadius + MediaFocusRing<RoundedRectangle>.outset)
        }
    }

    @Test("the ring's outset is its stroke width, so the stroke exactly fills the gap")
    func outsetMatchesTheStrokeWidth() {
        // `strokeBorder` strokes inward from the path. The ring is padded out by `outset`, so a
        // stroke of the same width spans exactly that gap and its inner edge meets the content.
        // Changing one without the other leaves either a gap or a stroke lying on the artwork.
        #expect(MediaFocusRing<RoundedRectangle>.outset == 4)
    }

    @Test("the on-panel stroke keeps its own width, and it is not the ring's")
    func panelStrokeIsThinnerThanTheRing() {
        #expect(FocusStroke.width == 3)
        // Deliberately different, and the reason is in the source: the ring owns the 4pt it is
        // padded into, while a panel stroke sits on an edge whose padding the content is laid out
        // against. Asserted so the two are never "unified" as a drift.
        #expect(FocusStroke.width != MediaFocusRing<RoundedRectangle>.outset)
    }

    // MARK: artwork corners

    @Test("the artwork corners keep their values, and the card stays tighter than the tile")
    func artworkCorners() {
        #expect(ArtworkCorner.card == 12)
        #expect(ArtworkCorner.tile == 16)
        #expect(ArtworkCorner.card < ArtworkCorner.tile)
    }

    /// The argument for two values rather than one, pinned because it is the thing that would make
    /// the split look like drift if it stopped being true. A library tile and an episode still are
    /// the SAME surface size on every tier, since `tileSize` is `landscapeSize` scaled, so the two
    /// radii cannot be explained by size. What separates them is whether the artwork is the subject
    /// or the ground behind a name (Sodalite#134).
    @Test("a tile and a landscape still are the same size, so the radius split is not about size")
    func tileAndLandscapeShareTheirSize() {
        for metrics in [LayoutMetrics.tv, .regular, .compact] {
            #expect(metrics.tileSize(cardScale: 1) == metrics.landscapeSize)
        }
    }
}
