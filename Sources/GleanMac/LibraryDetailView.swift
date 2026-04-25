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
                    inspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: .command)
                .help("Show metadata inspector")
                .disabled(store.record == nil)
            }
        }
        .task(id: citekey) {
            await store.load(citekey: citekey)
        }
    }

    @ViewBuilder
    private func pdfPane(for record: LibraryRecord) -> some View {
        if let url = pdfURL(for: record) {
            if FileManager.default.fileExists(atPath: url.path) {
                PDFViewer(url: url)
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
        let main = record.attachments.first(where: { $0.kind == "main" })
            ?? record.attachments.first
        guard let main else { return nil }
        let libraryRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/glean")
        return libraryRoot.appendingPathComponent(main.path)
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
