import SwiftUI
import AppKit
import os

private let log = Logger(subsystem: "com.miyawaki.glean-mac", category: "search")

/// Toolbar-placed search affordance that mirrors the System Settings
/// pattern: a circular magnifying-glass button by default, expands
/// inline into a search field when focused, collapses back when blurred
/// and empty. SwiftUI's `searchToolbarBehavior(.minimize)` would do
/// this for free, but Apple shipped that as iPhone/iPad only — the
/// macOS SDK marks it unavailable. So this rebuilds the same behavior
/// with primitives.
///
/// The TextField itself is an NSTextField wrapped via
/// NSViewRepresentable rather than SwiftUI's TextField, because
/// @FocusState doesn't bridge reliably through toolbar items —
/// makeFirstResponder() on AppKit's NSWindow does.
struct ExpandingSearch: View {
    @Binding var query: String
    var prompt: String = "Search"

    @State private var isExpanded = false

    var body: some View {
        Group {
            if isExpanded {
                expanded
            } else {
                collapsed
            }
        }
        .animation(.smooth(duration: 0.22), value: isExpanded)
    }

    private var collapsed: some View {
        Button {
            log.debug("search: expand-on-click")
            withAnimation(.smooth(duration: 0.22)) { isExpanded = true }
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .keyboardShortcut("f", modifiers: .command)
        .help("Search")
    }

    private var expanded: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            FocusableTextField(
                text: $query,
                placeholder: prompt,
                onCancel: collapse,
                onBlurIfEmpty: collapseIfEmpty
            )
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func collapse() {
        log.debug("search: collapse-via-esc")
        query = ""
        withAnimation(.smooth(duration: 0.22)) { isExpanded = false }
    }

    private func collapseIfEmpty() {
        if query.isEmpty {
            log.debug("search: collapse-on-blur-empty")
            withAnimation(.smooth(duration: 0.22)) { isExpanded = false }
        }
    }
}

#if DEBUG
/// NSTextField that pushes first-responder transitions into the
/// introspection registry. The HTTP /focus endpoint reads this. Lets a
/// closed-loop test assert "after the expand action, the search field
/// has focus" without polling pixels — catches the focus-binding race
/// where the field appears expanded but never actually takes the cursor.
final class IntrospectableNSTextField: NSTextField {
    let introspectionId: String

    init(introspectionId: String) {
        self.introspectionId = introspectionId
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func becomeFirstResponder() -> Bool {
        let did = super.becomeFirstResponder()
        if did {
            MainActor.assumeIsolated {
                IntrospectionRegistry.shared.focusedId = introspectionId
            }
        }
        return did
    }

    override func resignFirstResponder() -> Bool {
        let did = super.resignFirstResponder()
        if did {
            MainActor.assumeIsolated {
                if IntrospectionRegistry.shared.focusedId == introspectionId {
                    IntrospectionRegistry.shared.focusedId = nil
                }
            }
        }
        return did
    }
}
#endif

/// NSTextField wrapped for SwiftUI with explicit first-responder
/// management. Auto-focuses on first appearance and reports blur and
/// Esc up to the parent.
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onCancel: () -> Void
    let onBlurIfEmpty: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        #if DEBUG
        let field = IntrospectableNSTextField(introspectionId: "search.field")
        #else
        let field = NSTextField()
        #endif
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        // Ensure the field becomes first responder on first mount —
        // dispatched async because the view may not yet be in a window.
        if !context.coordinator.didFocusOnce {
            context.coordinator.didFocusOnce = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCancel: onCancel, onBlurIfEmpty: onBlurIfEmpty)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onCancel: () -> Void
        let onBlurIfEmpty: () -> Void
        var didFocusOnce = false

        init(text: Binding<String>,
             onCancel: @escaping () -> Void,
             onBlurIfEmpty: @escaping () -> Void) {
            self._text = text
            self.onCancel = onCancel
            self.onBlurIfEmpty = onBlurIfEmpty
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                text = field.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            #if DEBUG
            // AppKit equivalent of @FocusState's .onChange(of: isFocused). Fires
            // when the field editor takes over the field (i.e. the field is the
            // active text input). Asserts we're on main, since NSControl
            // notifications are delivered on the main thread.
            MainActor.assumeIsolated {
                IntrospectionRegistry.shared.focusedId = "search.field"
            }
            #endif
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            #if DEBUG
            MainActor.assumeIsolated {
                if IntrospectionRegistry.shared.focusedId == "search.field" {
                    IntrospectionRegistry.shared.focusedId = nil
                }
            }
            #endif
            // Only collapse if the user blurred to nothing — a Tab to
            // another field would also trigger this, but the parent
            // checks the query.isEmpty guard.
            DispatchQueue.main.async { [weak self] in
                self?.onBlurIfEmpty()
            }
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel()
                return true
            }
            return false
        }
    }
}
