import SwiftUI
import UIKit

/// SwiftUI wrapper around UIKit's UITextField. On tvOS, UITextField is
/// a first-class citizen of the UIKit focus engine — up/down routing
/// between the tab bar, the search bar, and the result rows is handled
/// cleanly, and activating the field reliably triggers the system
/// keyboard overlay. SwiftUI's own TextField on tvOS has subtle focus
/// quirks the UIKit equivalent doesn't share.
struct SearchTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void = {}

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        // tvOS UITextField defaults to a large system font; the
        // inline search bar looks chunky with it. Match .body-ish
        // sizing so the bar stays slim.
        field.font = UIFont.systemFont(ofSize: 26, weight: .regular)
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchTextField

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onCommit()
            textField.resignFirstResponder()
            return true
        }
    }
}
