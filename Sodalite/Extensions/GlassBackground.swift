import SwiftUI

struct GraphiteGlassBackground: View {
    var body: some View {
        #if os(iOS)
        Rectangle()
            .fill(.regularMaterial)
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.12), .white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        #else
        Rectangle()
            .fill(.regularMaterial)
            .ignoresSafeArea()
        #endif
    }
}

extension View {
    func glassBackground() -> some View {
        background { GraphiteGlassBackground() }
    }

    func themedStaticBackground(pausesMotion: Bool = true) -> some View {
        modifier(ThemedStaticBackgroundModifier(pausesMotion: pausesMotion))
    }

    func themedRootBackground() -> some View {
        modifier(ThemedRootBackgroundModifier())
    }

    func themedPresentationBackground() -> some View {
        modifier(ThemedPresentationBackgroundModifier())
    }
}

private struct IsolatedThemedSurface<Content: View>: View {
    let theme: ResolvedAppearanceTheme
    let depth: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AppBackgroundView(theme: theme, mode: .automatic)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.backgroundSurfaceDepth, depth)
    }
}

private struct ThemedRootBackgroundModifier: ViewModifier {
    @Environment(\.appearanceTheme) private var theme
    @Environment(\.backgroundSurfaceDepth) private var depth

    func body(content: Content) -> some View {
        IsolatedThemedSurface(theme: theme, depth: depth) {
            content
        }
    }
}

private struct ThemedPresentationBackgroundModifier: ViewModifier {
    @Environment(\.appearanceTheme) private var theme
    @Environment(\.backgroundSurfaceDepth) private var parentDepth

    @ViewBuilder
    func body(content: Content) -> some View {
        let surface = IsolatedThemedSurface(
            theme: theme,
            depth: parentDepth + 1
        ) {
            content
        }

        #if os(iOS)
        surface.presentationBackground(.clear)
        #else
        surface
        #endif
    }
}

private struct ThemedStaticBackgroundModifier: ViewModifier {
    @Environment(\.appearanceTheme) private var theme
    let pausesMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let renderedContent = content.background {
            // The same plate the isolated surfaces carry. Graphite Glass is a material and a tvOS
            // fullScreenCover keeps its presenter composited, so without this a backdrop-less page
            // samples the screen it was opened from.
            ZStack {
                Color.black.ignoresSafeArea()
                AppBackgroundView(theme: theme, mode: .static)
            }
        }

        if pausesMotion {
            renderedContent
                .pausesAppBackgroundMotion()
        } else {
            renderedContent
        }
    }
}
