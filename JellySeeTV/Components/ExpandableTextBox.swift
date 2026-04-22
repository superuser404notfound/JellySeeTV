import SwiftUI

struct ExpandableTextBox: View {
    let text: String
    @State private var showFullText = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 110)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFocused ? .white.opacity(0.1) : .white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .focusable()
            .focused($isFocused)
            .onLongPressGesture(minimumDuration: 0) {
                showFullText = true
            }
            .fullScreenCover(isPresented: $showFullText) {
                TextOverlay(text: text, isPresented: $showFullText)
            }
    }
}

struct TextOverlay: View {
    let text: String
    @Binding var isPresented: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(60)
                    .frame(maxWidth: 1200)
            }
            .focusable()
            .focused($isFocused)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(40)
                }
                Spacer()
            }
        }
    }
}
