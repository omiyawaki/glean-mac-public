import SwiftUI

struct LibraryView: View {
    let store: LibraryStore
    @Binding var selection: String?
    @State private var now = Date()
    @State private var query = ""

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, placeholder: "Search title or author")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                }
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
        .onReceive(ticker) { now = $0 }
    }

    private var filtered: [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter { entry in
            if entry.title.lowercased().contains(q) { return true }
            return entry.authors.contains { author in
                author.family.lowercased().contains(q)
                    || author.given.lowercased().contains(q)
            }
        }
    }

    private struct YearGroup {
        let year: Int?
        let entries: [LibraryEntry]
    }

    private var grouped: [YearGroup] {
        var byYear: [Int?: [LibraryEntry]] = [:]
        for e in filtered {
            byYear[e.year, default: []].append(e)
        }
        return byYear.keys.sorted { (a, b) in
            switch (a, b) {
            case (nil, _): return false
            case (_, nil): return true
            case (let x?, let y?): return x > y
            default: return false
            }
        }.map { YearGroup(year: $0, entries: byYear[$0] ?? []) }
    }

    private var subtitle: String {
        guard store.hasLoadedOnce else { return "" }
        let total = store.count
        let visible = filtered.count
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
