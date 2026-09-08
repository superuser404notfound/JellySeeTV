import SwiftUI

/// The ring half of the focus gesture. Its settle time is `FocusResponse.card`'s and not a literal:
/// the ring eased over 0.2 while every cast portrait and every Seerr episode still lifted over 0.15,
/// so the two halves of one gesture arrived at different times on the same element (Sodalite#130).
struct MediaFocusRing<Shape: InsettableShape>: View {
    let shape: Shape
    let isFocused: Bool

    @Environment(\.appearanceTheme) private var appearanceTheme

    var body: some View {
        shape
            .strokeBorder(
                appearanceTheme.palette.focus.color,
                lineWidth: 4
            )
            .padding(-4)
            .shadow(
                color: appearanceTheme.palette.focus.color.opacity(isFocused ? 0.32 : 0),
                radius: 9
            )
            .opacity(isFocused ? 1 : 0)
            .animation(FocusResponse.card.animation, value: isFocused)
            .accessibilityHidden(true)
    }
}
