import SwiftUI

/// A focusable card that handles tvOS focus without the default white border.
/// Use this instead of Button for media cards and settings tiles.
struct FocusableCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: (_ isFocused: Bool) -> Content

    @FocusState private var isFocused: Bool

    /// Corner radius of the cards this wrapper sits around. Both the
    /// poster/landscape MediaCard clipShape and the GenreCard clipShape
    /// use 12 — keep this in lockstep if either changes.
    private let cornerRadius: CGFloat = 12

    var body: some View {
        content(isFocused)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.tint, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .focusable()
            .focused($isFocused)
            .onLongPressGesture(minimumDuration: 0) {
                action()
            }
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 20, y: 10)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
