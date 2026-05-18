import SwiftUI

struct BacklogView: View {
    let store: BacklogStore
    let actionQueue: ActionQueueStore
    @Binding var selection: String?
    @State private var now = Date()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !store.hasLoadedOnce {
                if let message = store.lastError {
                    ContentUnavailableView {
                        Label("Couldn't load backlog", systemImage: "exclamationmark.triangle")
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
                    Section {
                        ForEach(store.entries) { entry in
                            BacklogRow(entry: entry).tag(entry.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Backlog")
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
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            for url in pdfs {
                actionQueue.enqueue(
                    title: "Attach PDF",
                    detail: url.lastPathComponent,
                    systemImage: "doc.richtext",
                    operation: {
                        try await IntakeActions.attach(file: url)
                    },
                    forceAttach: { citekey in
                        try await IntakeActions.attach(file: url, citekey: citekey)
                    }
                )
            }
            return !pdfs.isEmpty
        }
    }

    private var subtitle: String {
        guard store.hasLoadedOnce else { return "" }
        let countPart = store.count == 1
            ? "1 paper awaiting PDF"
            : "\(store.count) papers awaiting PDFs"
        guard let when = store.lastRefreshedAt else { return countPart }
        return "\(countPart) • \(relativeUpdated(from: when, to: now))"
    }
}

private struct BacklogRow: View {
    let entry: BacklogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(entry.citekey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.doi)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
