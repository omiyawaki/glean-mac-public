import SwiftUI
import AppKit

/// AppKit's NSSearchField wrapped for SwiftUI. Used for column-scoped
/// search that sits inline above its List, instead of going through
/// `.searchable` which always promotes to the unified window toolbar
/// on macOS. Bounds the search field's width to the list column, so it
/// stays cohesive when the inspector toggles. Also gives us the native
/// magnifying-glass icon, clear button, and recent-searches menu for
/// free.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text = field.stringValue
        }
    }
}
