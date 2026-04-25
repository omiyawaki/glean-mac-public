import SwiftUI

/// Toolbar-placed search affordance that mirrors the System Settings
/// pattern: a circular magnifying-glass button by default, expands
/// inline into a search field when focused, collapses back when blurred
/// and empty. SwiftUI's `searchToolbarBehavior(.minimize)` would do
/// this for free, but Apple shipped that as iPhone/iPad only — the
/// macOS SDK marks it unavailable. So this rebuilds the same behavior
/// with primitives.
struct ExpandingSearch: View {
    @Binding var query: String
    var prompt: String = "Search"

    @State private var isExpanded = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isExpanded {
                expanded
            } else {
                collapsed
            }
        }
        .animation(.smooth(duration: 0.22), value: isExpanded)
        .onChange(of: isFocused) { _, focused in
            if !focused && query.isEmpty {
                withAnimation(.smooth(duration: 0.22)) { isExpanded = false }
            }
        }
    }

    private var collapsed: some View {
        Button {
            withAnimation(.smooth(duration: 0.22)) { isExpanded = true }
            // Defer focus until the TextField has been mounted.
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                isFocused = true
            }
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
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
                .onExitCommand {
                    query = ""
                    isFocused = false
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    isFocused = true
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
}
