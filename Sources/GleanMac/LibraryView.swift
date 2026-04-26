import SwiftUI

struct LibraryView: View {
    let store: LibraryStore
    @Binding var selection: String?
    @Binding var query: String
    @State private var now = Date()
    @State private var grouped: [YearGroup] = []
    @State private var visibleCount: Int = 0

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
                    ForEach(grouped, id: \.year) { group in
                        Section(group.year.map { String($0) } ?? "Undated") {
                            ForEach(group.entries) { entry in
                                LibraryRow(entry: entry).tag(entry.id)
                            }
                        }
                    }
                }
                .animation(nil, value: grouped)
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
    /// stable value across body re-evaluations. Without this, the
    /// grouped result was rebuilt on every render — including the
    /// per-character renders triggered by the search field bindings —
    /// and clearing a non-empty filter caused a beach-ball as SwiftUI
    /// tried to redraw 5000+ rows in a single frame.
    private func recomputeGroups() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let entries: [LibraryEntry]
        if q.isEmpty {
            entries = store.entries
        } else {
            entries = store.entries.filter { entry in
                if entry.title.lowercased().contains(q) { return true }
                return entry.authors.contains { author in
                    author.family.lowercased().contains(q)
                        || author.given.lowercased().contains(q)
                }
            }
        }

        var byYear: [Int?: [LibraryEntry]] = [:]
        byYear.reserveCapacity(120)
        for e in entries {
            byYear[e.year, default: []].append(e)
        }
        let newGrouped = byYear.keys.sorted { (a, b) in
            switch (a, b) {
            case (nil, _): return false
            case (_, nil): return true
            case (let x?, let y?): return x > y
            default: return false
            }
        }.map { YearGroup(year: $0, entries: byYear[$0] ?? []) }

        visibleCount = entries.count
        grouped = newGrouped
    }

    fileprivate struct YearGroup: Equatable {
        let year: Int?
        let entries: [LibraryEntry]
    }

    private var subtitle: String {
        guard store.hasLoadedOnce else { return "" }
        let total = store.count
        let visible = visibleCount
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
