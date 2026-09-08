import SwiftUI

/// What the cover has to supply around a tvOS menu, which depends on what the panel already draws.
enum MenuPanelStyle {
    /// The cover draws the card. For content that filled the system sheet's card and relied on it
    /// for the inset and the rounded corner (the sort and version pickers, the trust prompt).
    case card
    /// Scrim only. For content that already carries its own panel or fills the screen itself (the
    /// deletion and request-edit sheets, the server switcher, the diagnostic log).
    case plain
}

extension View {
    /// Presents a menu panel: tvOS as a cover that carries its own scrim, iOS as the system sheet.
    ///
    /// A tvOS `.sheet` darkens the whole page behind it on UIKit's curve, and that curve is a
    /// step, not a fade: measured at 60 Hz against the sort panel in the tvOS 26 simulator, it
    /// takes a white page from 220 to 135 in 223 ms with 51% of the drop inside the first 83 ms,
    /// next to the app's own overlays, which fade in 0.2 to 0.4 s. A cover gets no system dim, so
    /// the scrim is ours and eases: 231 to 116 over 265 ms, 20% of it in the first 83 ms. The end
    /// state is the one the system had (its dim measures as black at 0.45, one notch off
    /// `Color.Theme.scrim`), only the way there changes.
    ///
    /// This is the presentation the app's other tvOS menus already use (`CatalogPickerSheet`,
    /// `TextOverlay`, the changelog and licence readers).
    func menuPresentation<Content: View>(
        isPresented: Binding<Bool>,
        panel: MenuPanelStyle = .card,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(tvOS)
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            MenuPanelCover(panel: panel, dismiss: { isPresented.wrappedValue = false }, content: content)
        }
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }

    /// `item:` form, for the panels that carry their subject in the binding.
    func menuPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        panel: MenuPanelStyle = .card,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(tvOS)
        fullScreenCover(item: item, onDismiss: onDismiss) { value in
            MenuPanelCover(panel: panel, dismiss: { item.wrappedValue = nil }) { content(value) }
        }
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}

#if os(tvOS)
/// The scrim, and for `.card` the card, that a tvOS sheet used to get from UIKit, drawn here so
/// both arrive on the app's own timing. The inset is the app-wide 10-foot one, so the page still
/// frames the panel the way the system card did.
private struct MenuPanelCover<Content: View>: View {
    let panel: MenuPanelStyle
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var shown = false

    var body: some View {
        ZStack {
            // Only the scrim is animated. Fading the panel too would put the focusable rows at
            // alpha 0 for the frames in which tvOS commits first focus, and UIKit does not focus
            // what it cannot see; the panel rides the cover's own dissolve instead.
            Color.Theme.scrim
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)

            switch panel {
            case .card:
                content()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
                    .padding(.horizontal, 80)
                    .padding(.vertical, 60)
            case .plain:
                content()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.35)) { shown = true }
        }
        // A cover does not leave on Menu by itself, unlike the sheet this replaces. A panel that
        // handles Menu itself (the diagnostic log) sits deeper and still wins.
        .onExitCommandCompat { dismiss() }
    }
}
#endif
