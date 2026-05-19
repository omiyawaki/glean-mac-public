import SwiftUI

struct BacklogView: View {
    let store: BacklogStore
    let actionQueue: ActionQueueStore
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void
    let retryPDF: (BacklogEntry, Bool) async -> Void
    @Binding var selection: String?

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
                                       },
                                       onTryFetchingPDF: {
                                           let isAlreadySelected = selection == entry.id
                                           Task { await retryPDF(entry, isAlreadySelected) }
                                       })
                                .tag(entry.id)
                        }
                    }
                }
            }
        }
        .task {
            if !store.hasLoadedOnce { await store.load() }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            for url in pdfs {
                actionQueue.enqueue(
                    title: "Attach PDF",
                    detail: url.lastPathComponent,
                    systemImage: "doc.richtext",
                    operation: {
                        try await offlineCoordinator.queueAttachPDF(url)
                        trashSourcePDF(url)
                        await syncPendingOperations()
                    },
                    forceAttach: { citekey in
                        try await offlineCoordinator.queueAttachPDF(url, citekey: citekey)
                        trashSourcePDF(url)
                        await syncPendingOperations()
                    }
                )
            }
            return !pdfs.isEmpty
        }
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
                    try await offlineCoordinator.queueAttachPDF(url, citekey: citekey)
                    trashSourcePDF(url)
                    await syncPendingOperations()
                },
                forceAttach: { altCitekey in
                    try await offlineCoordinator.queueAttachPDF(url, citekey: altCitekey)
                    trashSourcePDF(url)
                    await syncPendingOperations()
                }
            )
        }
    }
}

/// Move a successfully-attached source PDF to the user's Trash. The
/// PDF lives in the glean library now, so the original copy under
/// ~/Downloads (or wherever the drop came from) is duplicate state.
/// Trash rather than unlink so the user has a recovery path if the
/// attach turns out to be the wrong entry: the file is fishable out
/// of Finder until they empty Trash.
///
/// Best-effort — non-file URLs, read-only volumes, or already-deleted
/// paths fail silently. The attach itself already succeeded; surfacing
/// a trash failure would just confuse the user.
@MainActor
private func trashSourcePDF(_ url: URL) {
    guard url.isFileURL else { return }
    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
}

private struct BacklogRow: View {
    let entry: BacklogEntry
    let onDropPDFs: ([URL]) -> Void
    let onTryFetchingPDF: () -> Void
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
            Text(entry.statusText)
                .font(.caption)
                .foregroundStyle(statusStyle)
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
        .contextMenu {
            Button {
                onTryFetchingPDF()
            } label: {
                Label(BacklogPDFManualFetchPresentation.menuTitle,
                      systemImage: BacklogPDFManualFetchPresentation.systemImage)
            }
            .disabled(!BacklogPDFManualFetchPresentation.isAvailable(for: entry))
        }
        .dropDestination(for: URL.self) { urls, _ in
            onDropPDFs(urls)
            return urls.contains { $0.pathExtension.lowercased() == "pdf" }
        } isTargeted: { isDropTargeted = $0 }
    }

    private var statusStyle: HierarchicalShapeStyle {
        switch entry.state {
        case .automatedFetchFailed, .attachmentFileMissing:
            .secondary
        default:
            .tertiary
        }
    }
}
