import SwiftUI

struct GlassActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isProminent: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body)
            Text(title)
                .font(.callout)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(backgroundFill)
        )
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 10, y: 5)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .focusable()
        .focused($isFocused)
        .onLongPressGesture(minimumDuration: 0) {
            action()
        }
    }

    private var backgroundFill: AnyShapeStyle {
        if isProminent {
            return AnyShapeStyle(isFocused ? Color.accentColor.opacity(0.9) : Color.accentColor.opacity(0.7))
        }
        return AnyShapeStyle(isFocused ? .white.opacity(0.2) : .white.opacity(0.1))
    }
}
