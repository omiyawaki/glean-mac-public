import SwiftUI
import AppKit

struct BacklogDetailView: View {
    let entry: BacklogEntry?
    let actionQueue: ActionQueueStore
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void
    let retryPDF: (BacklogEntry, Bool) async -> Void
    @Binding var inspectorPresented: Bool
    @State private var actionError: String?
    @State private var showError = false
    @State private var isRetryingPDF = false

    var body: some View {
        Group {
            if let entry, let url = doiURL(for: entry) {
                WebViewer(url: url) { downloadedURL in
                    // Forward the currently-selected entry's citekey so
                    // /attach can force-attach to it rather than guessing
                    // by extracting a DOI from the PDF text. Critical for
                    // older Physics Today / similar legacy publishers whose
                    // PDFs don't print their own DOI anywhere — body text
                    // only contains DOIs of cited works.
                    let ck = entry.citekey
                    actionQueue.enqueue(
                        title: "Attach PDF",
                        detail: downloadedURL.lastPathComponent,
                        systemImage: "doc.richtext"
                    ) {
                        try await offlineCoordinator.queueAttachPDF(downloadedURL,
                                                                    citekey: ck)
                        await syncPendingOperations()
                    }
                } onDownloadFailed: { message in
                    actionError = message
                    showError = true
                }
                    .navigationTitle(entry.title)
                    .navigationSubtitle(entry.doi)
            } else if entry != nil {
                ContentUnavailableView(
                    "No DOI to open",
                    systemImage: "link",
                    description: Text("This backlog entry has no resolvable DOI.")
                )
            } else {
                ContentUnavailableView(
                    "No paper selected",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Choose a paper from the backlog to find its PDF online, then drop the file onto the row to attach it.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let entry else { return }
                    Task {
                        isRetryingPDF = true
                        defer { isRetryingPDF = false }
                        await retryPDF(entry, true)
                    }
                } label: {
                    Label(BacklogPDFManualFetchPresentation.toolbarTitle,
                          systemImage: BacklogPDFManualFetchPresentation.systemImage)
                }
                .help("Try fetching this paper's PDF in the current WebView")
                .disabled(
                    !BacklogPDFManualFetchPresentation.isAvailable(for: entry) ||
                    isRetryingPDF
                )
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let entry, let url = doiURL(for: entry) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
                .keyboardShortcut("l", modifiers: .command)
                .help("Open this DOI in Safari")
                .disabled(entry == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: .command)
                .help("Show metadata inspector")
                .disabled(entry == nil)
            }
        }
        .alert("PDF handling failed",
               isPresented: $showError,
               presenting: actionError) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    private func doiURL(for entry: BacklogEntry) -> URL? {
        guard !entry.doi.isEmpty else { return nil }
        return URL(string: "https://doi.org/\(entry.doi)")
    }
}
