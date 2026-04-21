import SwiftUI

/// Brand splash shown while AppRouter restores the session.
/// Replaces the previous bare `ProgressView()` so the user gets a
/// proper "app is opening" moment instead of a spinner-on-black flash.
///
/// Animation: logo fades in and grows slightly from 80% → 100% over
/// `appearDuration`, holds for `holdDuration`, then fades out. The
/// minimum on-screen time is `appearDuration + holdDuration` so the
/// splash never just blinks past on a fast session restore.
///
/// Supporters see the gold "Premium" variant rendered in its original
/// colors. Everyone else sees the standard white template logo.
struct SplashView: View {

    @Environment(\.dependencies) private var dependencies

    private let appearDuration: Double = 0.6
    private let holdDuration: Double = 0.6

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            logo
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

    @ViewBuilder
    private var logo: some View {
        if dependencies.storeKitService.isSupporter {
            // Premium logo ships with original rendering intent, so the
            // gold color comes through without a `renderingMode` override.
            Image("PremiumLogo_Hero")
                .resizable()
        } else {
            Image("Logo")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.white)
        }
    }

    /// Total minimum time the splash should remain on screen.
    static let minimumDisplayDuration: Double = 1.2
}
