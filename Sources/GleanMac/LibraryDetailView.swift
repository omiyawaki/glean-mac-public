import SwiftUI
import Observation

@MainActor
@Observable
final class LibraryDetailStore {
    var record: LibraryRecord?
    var isLoading: Bool = false
    var error: String?
    var loadedCitekey: String?

    private let baseURL = URL(string: "http://backend.example.com:8766")!

    func load(citekey: String?) async {
        guard let citekey else {
            record = nil
            loadedCitekey = nil
            return
        }
        if loadedCitekey == citekey, record != nil { return }
        isLoading = true
        defer { isLoading = false }
        let path = "/api/papers/" + (citekey.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? citekey)
        let url = baseURL.appendingPathComponent(path)
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                error = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                return
            }
            let decoded = try JSONDecoder().decode(LibraryRecord.self, from: data)
            withAnimation(.smooth) {
                record = decoded
                loadedCitekey = citekey
                error = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct LibraryDetailView: View {
    let citekey: String?
    let store: LibraryDetailStore
    @Binding var inspectorPresented: Bool
    @Binding var query: String
    /// nil = follow system appearance, non-nil = user override.
    @State private var pdfDarkModeOverride: Bool?
    @State private var thumbnailSidebarVisible = true
    @Environment(\.colorScheme) private var systemColorScheme

    private var pdfDarkMode: Bool {
        pdfDarkModeOverride ?? (systemColorScheme == .dark)
    }

    var body: some View {
        Group {
            if citekey == nil {
                ContentUnavailableView(
                    "No paper selected",
                    systemImage: "doc.text",
                    description: Text("Choose a paper from the list to read it.")
                )
            } else if store.loadedCitekey == citekey, let record = store.record {
                pdfPane(for: record)
                    .navigationTitle(record.title)
                    .navigationSubtitle(authorYearLine(record))
            } else if let message = store.error {
                ContentUnavailableView {
                    Label("Couldn't load record", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await store.load(citekey: citekey) } }
                        .buttonStyle(.glassProminent)
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    pdfDarkModeOverride = !pdfDarkMode
                } label: {
                    Label(
                        pdfDarkMode ? "Light PDF" : "Dark PDF",
                        systemImage: pdfDarkMode ? "sun.max" : "moon"
                    )
                }
                .help(pdfDarkMode
                      ? "Render PDF with light page background"
                      : "Render PDF with dark page background (inverts colors)")
                .disabled(store.record == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    thumbnailSidebarVisible.toggle()
                } label: {
                    Label(
                        thumbnailSidebarVisible ? "Hide Thumbnails" : "Show Thumbnails",
                        systemImage: "sidebar.right"
                    )
                }
                .help(thumbnailSidebarVisible
                      ? "Hide PDF page thumbnails"
                      : "Show PDF page thumbnails")
                .disabled(openablePDFURL == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ExternalPDFOpener.system.open(openablePDFURL)
                } label: {
                    Label("Open PDF", systemImage: "arrow.up.right.square")
                }
                .help("Open this PDF in the default PDF viewer")
                .disabled(openablePDFURL == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: .command)
                .help("Show metadata inspector")
                .disabled(store.record == nil)
            }
            ToolbarSpacer()
            ToolbarItem(placement: .primaryAction) {
                ExpandingSearch(query: $query, prompt: "Search title or author")
            }
        }
        .task(id: citekey) {
            await store.load(citekey: citekey)
        }
    }

    private var openablePDFURL: URL? {
        guard let record = store.record,
              let url = pdfURL(for: record),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return url
    }

    @ViewBuilder
    private func pdfPane(for record: LibraryRecord) -> some View {
        if let url = pdfURL(for: record) {
            if FileManager.default.fileExists(atPath: url.path) {
                PDFViewer(
                    url: url,
                    darkMode: pdfDarkMode,
                    thumbnailSidebarVisible: thumbnailSidebarVisible
                )
            } else {
                ContentUnavailableView {
                    Label("PDF not downloaded", systemImage: "icloud.and.arrow.down")
                } description: {
                    Text("This file is stored in iCloud and hasn't synced to this Mac yet. Open it in Finder to trigger a download.")
                } actions: {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        } else {
            ContentUnavailableView(
                "No PDF attached",
                systemImage: "doc",
                description: Text("This record has no PDF attachment.")
            )
        }
    }

    private func pdfURL(for record: LibraryRecord) -> URL? {
        LibraryPDFLocator.default.pdfURL(for: record)
    }

    private func authorYearLine(_ record: LibraryRecord) -> String {
        let names = record.authors.map { $0.family }
        let authorPart: String
        switch names.count {
        case 0: authorPart = ""
        case 1: authorPart = names[0]
        case 2: authorPart = "\(names[0]) & \(names[1])"
        default: authorPart = "\(names[0]) et al."
        }
        if let year = record.year {
            return authorPart.isEmpty ? "\(year)" : "\(authorPart) · \(year)"
        }
        return authorPart
    }
}
