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
                            BacklogRow(entry: entry,
                                       onDropPDFs: { urls in
                                           enqueueForceAttach(urls: urls,
                                                              citekey: entry.citekey)
                                       })
                                .tag(entry.id)
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

    /// Drop-on-row force-attach. Skips the server's DOI extraction by
    /// passing an explicit citekey, same path the force-attach menu
    /// takes after a no_doi failure. Used when the user has already
    /// chosen which backlog entry a PDF belongs to (often: pre-DOI
    /// papers, or PDFs whose body doesn't print the DOI).
    private func enqueueForceAttach(urls: [URL], citekey: String) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        for url in pdfs {
            actionQueue.enqueue(
                title: "Attach PDF",
                detail: url.lastPathComponent,
                systemImage: "doc.richtext",
                operation: {
                    try await IntakeActions.attach(file: url, citekey: citekey)
                },
                forceAttach: { altCitekey in
                    try await IntakeActions.attach(file: url, citekey: altCitekey)
                }
            )
        }
    }
}

private struct BacklogRow: View {
    let entry: BacklogEntry
    let onDropPDFs: ([URL]) -> Void
    @State private var isDropTargeted = false

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
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear,
                              lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            onDropPDFs(urls)
            return urls.contains { $0.pathExtension.lowercased() == "pdf" }
        } isTargeted: { isDropTargeted = $0 }
    }
}
