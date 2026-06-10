import SwiftUI

enum LibraryRowLayout {
    static let rowHeight: CGFloat = 72
}

struct LibraryView: View {
    let store: LibraryStore
    let listState: LibraryListState
    @Binding var selection: String?
    @Binding var query: String

    var body: some View {
        Group {
            if !store.hasLoadedOnce {
                if let message = store.lastError {
                    ContentUnavailableView {
                        Label("Couldn't load library", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { Task { await store.load() } }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ProgressView().controlSize(.large)
                }
            } else {
                let isFiltering = LibraryListIdentity.value(forQuery: query) == "library-filtered"
                ZStack {
                    libraryList(
                        groups: listState.allGrouped,
                        identity: "library-all",
                        isHidden: isFiltering
                    )
                    libraryList(
                        groups: listState.filteredGrouped,
                        identity: "library-filtered",
                        isHidden: !isFiltering
                    )
                }
                .animation(nil, value: isFiltering)
            }
        }
    }

    @ViewBuilder
    private func libraryList(
        groups: [LibraryFilter.YearGroup],
        identity: String,
        isHidden: Bool
    ) -> some View {
        List(selection: $selection) {
            ForEach(groups, id: \.year) { group in
                Section(group.year.map { String($0) } ?? "Undated") {
                    ForEach(group.entries) { entry in
                        LibraryRow(entry: entry).tag(entry.id)
                    }
                }
            }
        }
        .animation(nil, value: groups)
        .id(identity)
        .environment(\.defaultMinListRowHeight, LibraryRowLayout.rowHeight)
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .accessibilityHidden(isHidden)
    }
}

private struct LibraryRow: View {
    let entry: LibraryEntry

    /// Fixed-height rows keep search-clear from triggering thousands of
    /// automatic row-height measurements while still leaving room for a
    /// two-line title plus the author line.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(2)
            Text(authorLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .frame(height: LibraryRowLayout.rowHeight, alignment: .center)
        .help(entry.title)
    }

    private var authorLine: String {
        let names = entry.authors.map { $0.family }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return "\(names[0]) et al."
        }
    }
}
