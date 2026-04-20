import SwiftUI

/// Brand splash shown while AppRouter restores the session.
/// Replaces the previous bare `ProgressView()` so the user gets a
/// proper "app is opening" moment instead of a spinner-on-black flash.
///
/// Animation: logo fades in and grows slightly from 80% → 100% over
/// `appearDuration`, holds for `holdDuration`, then fades out. The
/// minimum on-screen time is `appearDuration + holdDuration` so the
/// splash never just blinks past on a fast session restore.
struct SplashView: View {

    private let appearDuration: Double = 0.6
    private let holdDuration: Double = 0.6

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Image("Logo")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.white)
                .aspectRatio(contentMode: .fit)
                .frame(width: 280, height: 280)
                .scaleEffect(hasAppeared ? 1.0 : 0.8)
                .opacity(hasAppeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: appearDuration)) {
                hasAppeared = true
            }
        }
    }

    /// Total minimum time the splash should remain on screen.
    static let minimumDisplayDuration: Double = 1.2
}

#Preview {
    SplashView()
}
