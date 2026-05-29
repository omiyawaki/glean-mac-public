import SwiftUI

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
                List(selection: $selection) {
                    ForEach(listState.grouped, id: \.year) { group in
                        Section(group.year.map { String($0) } ?? "Undated") {
                            ForEach(group.entries) { entry in
                                LibraryRow(entry: entry).tag(entry.id)
                            }
                        }
                    }
                }
                .animation(nil, value: listState.grouped)
            }
        }
        .task {
            if !store.hasLoadedOnce { await store.load() }
        }
        .task(id: query) {
            recomputeGroups()
        }
        .task(id: store.entries.count) {
            recomputeGroups()
        }
    }

    /// Recompute filter + year grouping into @State so the List sees a
    /// stable value across body re-evaluations. The pure logic lives
    /// in LibraryFilter (covered by tests).
    private func recomputeGroups() {
        listState.update(entries: store.entries, query: query)
    }
}

private struct LibraryRow: View {
    let entry: LibraryEntry

    /// Variable-height row. The title is allowed to wrap to two lines when
    /// the list column is wide enough; the row grows vertically as needed.
    /// This eliminates the previous situation where a hard 52 pt cap made
    /// `.lineLimit(2)` ineffective and caused early truncation even with
    /// plenty of horizontal space.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(2)   // Rows size naturally; title may wrap to 2 lines when the list column is wide.
            Text(authorLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
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
