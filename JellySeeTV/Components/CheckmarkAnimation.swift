import SwiftUI

struct CheckmarkAnimation: View {
    @State private var trimEnd: CGFloat = 0
    @State private var circleScale: CGFloat = 0.8
    @State private var circleOpacity: Double = 0
    @State private var checkOpacity: Double = 0

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.green.opacity(0.15))
                .frame(width: 120, height: 120)
                .scaleEffect(circleScale)
                .opacity(circleOpacity)

            // Circle stroke
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))

            // Checkmark
            Path { path in
                path.move(to: CGPoint(x: 35, y: 62))
                path.addLine(to: CGPoint(x: 52, y: 78))
                path.addLine(to: CGPoint(x: 85, y: 42))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            .frame(width: 120, height: 120)
            .opacity(checkOpacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                circleScale = 1.0
                circleOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 0.5).delay(0.15)) {
                trimEnd = 1.0
                checkOpacity = 1.0
            }
        }
    }
}
