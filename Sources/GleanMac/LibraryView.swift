import SwiftUI

struct LibraryView: View {
    let store: LibraryStore
    let listState: LibraryListState
    @Binding var selection: String?
    @Binding var query: String
    @State private var now = Date()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
        .navigationTitle("All Papers")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RefreshButton(isLoading: store.isLoading) {
                    await store.load()
                }
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
        .onReceive(ticker) { now = $0 }
    }

    /// Recompute filter + year grouping into @State so the List sees a
    /// stable value across body re-evaluations. The pure logic lives
    /// in LibraryFilter (covered by tests).
    private func recomputeGroups() {
        listState.update(entries: store.entries, query: query)
    }

    private var subtitle: String {
        guard store.hasLoadedOnce else { return "" }
        let total = store.count
        let visible = listState.visibleCount
        let countPart: String
        if visible == total {
            countPart = total == 1 ? "1 paper" : "\(total) papers"
        } else {
            countPart = "\(visible) of \(total) papers"
        }
        guard let when = store.lastRefreshedAt else { return countPart }
        return "\(countPart) • \(relativeUpdated(from: when, to: now))"
    }
}

private struct LibraryRow: View {
    let entry: LibraryEntry

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
        .padding(.vertical, 2)
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
