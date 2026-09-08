import SwiftUI

/// The ring half of the focus gesture. Its settle time is `FocusResponse.card`'s and not a literal:
/// the ring eased over 0.2 while every cast portrait and every Seerr episode still lifted over 0.15,
/// so the two halves of one gesture arrived at different times on the same element (Sodalite#130).
///
/// Prefer ``init(cornerRadius:isFocused:)``. The ring is drawn `outset` points OUTSIDE the content
/// it marks, and a rounded rectangle offset outward by d has radius `r + d`, so a ring that reuses
/// the content's radius rounds tighter than the corner it hugs and leaves the ground showing as a
/// dark crescent in each corner. Five of the seven rectangular sites did exactly that, because a
/// bare `Shape` parameter asks every call site to know a geometry rule that nothing states
/// (Sodalite#134). Passing the CONTENT's radius and letting the ring derive its own removes the
/// question. The shape initializer stays for `Capsule`, which is unaffected: a capsule offset
/// outward is still a capsule.
struct MediaFocusRing<Shape: InsettableShape>: View {
    let shape: Shape
    let isFocused: Bool

    /// How far outside the content the ring sits. Also its stroke width, since `strokeBorder`
    /// strokes inward from the path: the stroke therefore spans exactly the gap it is padded into,
    /// and its inner edge lands on the content's own edge.
    static var outset: CGFloat { 4 }

    @Environment(\.appearanceTheme) private var appearanceTheme

    var body: some View {
        shape
            .strokeBorder(
                appearanceTheme.palette.focus.color,
                lineWidth: Self.outset
            )
            .padding(-Self.outset)
            .shadow(
                color: appearanceTheme.palette.focus.color.opacity(isFocused ? 0.32 : 0),
                radius: 9
            )
            .opacity(isFocused ? 1 : 0)
            .animation(FocusResponse.card.animation, value: isFocused)
            .accessibilityHidden(true)
    }
}

extension MediaFocusRing where Shape == RoundedRectangle {

    /// Rings a rounded-rectangular content of `cornerRadius`, staying concentric with it.
    init(cornerRadius: CGFloat, isFocused: Bool) {
        self.init(
            shape: RoundedRectangle(cornerRadius: cornerRadius + MediaFocusRing.outset),
            isFocused: isFocused
        )
    }
}

/// The on-panel focus stroke, the sibling of ``MediaFocusRing``. The two widths look like drift and
/// are not: the ring is drawn OUTSIDE artwork it must not cover, so it owns the 4pt it is padded
/// into, while this one is drawn INSIDE a panel's own edge, where 4pt would eat the padding the
/// content is laid out against. What was drift is that three rows carried 2 and one card carried 4
/// against 36 at 3 (Sodalite#134).
enum FocusStroke {
    /// Width of the tinted stroke on a panel, a row, a tile or a chip.
    static let width: CGFloat = 3
}

extension View {

    /// Draws the app's focus stroke on this view's own edge.
    func focusStroke<S: InsettableShape>(_ shape: S, isFocused: Bool) -> some View {
        overlay(
            shape
                .strokeBorder(.tint, lineWidth: FocusStroke.width)
                .opacity(isFocused ? 1 : 0)
        )
    }

    /// Convenience for the common rounded-rectangular panel.
    func focusStroke(cornerRadius: CGFloat, isFocused: Bool) -> some View {
        focusStroke(RoundedRectangle(cornerRadius: cornerRadius), isFocused: isFocused)
    }
}
