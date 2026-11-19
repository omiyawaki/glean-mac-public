import SwiftUI
import Observation

@MainActor
@Observable
final class LibraryDetailStore {
    typealias LoadRecord = (String) async throws -> LibraryRecord

    var record: LibraryRecord?
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var error: String?
    var loadedCitekey: String?

    private let loadRecord: LoadRecord
    private let recordCache: LibraryRecordCacheStore
    private var loadGeneration = 0

    init(
        endpoints: GleanBackendEndpoints = .configured,
        recordCache: LibraryRecordCache = .default
    ) {
        let recordLoader = LibraryRecordLoader(endpoints: endpoints)
        loadRecord = { citekey in
            try await recordLoader.load(citekey: citekey)
        }
        self.recordCache = LibraryRecordCacheStore(cache: recordCache)
    }

    init(
        recordCache: LibraryRecordCache = .default,
        loadRecord: @escaping LoadRecord
    ) {
        self.loadRecord = loadRecord
        self.recordCache = LibraryRecordCacheStore(cache: recordCache)
    }

    func displayedRecord(for citekey: String?) -> LibraryRecord? {
        guard let citekey else { return nil }
        if loadedCitekey == citekey, let record {
            return record
        }
        return recordCache.record(for: citekey)
    }

    func load(citekey: String?) async {
        loadGeneration &+= 1
        let generation = loadGeneration

        guard let citekey else {
            record = nil
            loadedCitekey = nil
            error = nil
            isLoading = false
            isRefreshing = false
            return
        }
        if loadedCitekey == citekey, record != nil {
            error = nil
            isLoading = false
            return
        }

        let cachedRecord = recordCache.record(for: citekey)
        if let cachedRecord {
            record = cachedRecord
            loadedCitekey = citekey
            recordCache.touch(citekey)
        }
        error = nil
        isLoading = cachedRecord == nil
        isRefreshing = cachedRecord != nil
        defer {
            if loadGeneration == generation {
                isLoading = false
                isRefreshing = false
            }
        }
        do {
            let decoded = try await loadRecord(citekey)
            guard loadGeneration == generation, !Task.isCancelled else { return }
            if record != decoded {
                record = decoded
            }
            loadedCitekey = citekey
            error = nil
            recordCache.insert(decoded)
        } catch {
            guard loadGeneration == generation else { return }
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            // A stale cached record is still fully usable. Keep it visible and
            // treat a failed background refresh as nonblocking.
            if cachedRecord == nil {
                self.error = error.localizedDescription
            }
        }
    }

    func refresh(citekey: String?) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        guard let citekey else {
            record = nil
            loadedCitekey = nil
            error = nil
            isLoading = false
            isRefreshing = false
            return
        }
        isRefreshing = record != nil
        isLoading = record == nil
        defer {
            if loadGeneration == generation {
                isLoading = false
                isRefreshing = false
            }
        }
        do {
            let decoded = try await loadRecord(citekey)
            guard loadGeneration == generation, !Task.isCancelled else { return }
            record = decoded
            loadedCitekey = citekey
            error = nil
            recordCache.insert(decoded)
        } catch {
            guard loadGeneration == generation else { return }
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if record == nil {
                self.error = error.localizedDescription
            }
        }
    }
}

struct LibraryDetailView: View {
    let citekey: String?
    let store: LibraryDetailStore
    let actionQueue: ActionQueueStore
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void
    @Binding var inspectorPresented: Bool
    @Binding var query: String
    /// nil = follow system appearance, non-nil = user override.
    @State private var pdfDarkModeOverride: Bool?
    @State private var thumbnailSidebarVisible = true
    @State private var isDropTargeted = false
    @State private var materializedPDF: LibraryPDFAvailability?
    @Environment(\.colorScheme) private var systemColorScheme

    private var pdfDarkMode: Bool {
        pdfDarkModeOverride ?? (systemColorScheme == .dark)
    }

    private var displayedRecord: LibraryRecord? {
        store.displayedRecord(for: citekey)
    }

    var body: some View {
        Group {
            if citekey == nil {
                ContentUnavailableView(
                    "No paper selected",
                    systemImage: "doc.text",
                    description: Text("Choose a paper from the list to read it.")
                )
            } else if let record = displayedRecord {
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
                .disabled(displayedRecord == nil)
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
                .disabled(displayedRecord == nil)
            }
            ToolbarSpacer()
            ToolbarItem(placement: .primaryAction) {
                ExpandingSearch(query: $query, prompt: "Search title or author")
            }
        }
        .task(id: citekey) {
            await store.load(citekey: citekey)
        }
        .task(id: pdfMaterializeKey) {
            materializedPDF = nil
            guard let record = displayedRecord else { return }
            materializedPDF = await LibraryPDFMaterializer.system.prepare(record: record)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let targetCitekey = displayedRecord?.citekey ?? citekey
            return BacklogPDFDropRouting.enqueueForceAttach(
                urls: urls,
                citekey: targetCitekey,
                actionQueue: actionQueue,
                offlineCoordinator: offlineCoordinator,
                syncPendingOperations: syncPendingOperations,
                onPlaced: {
                    await store.refresh(citekey: targetCitekey)
                }
            )
        } isTargeted: { isDropTargeted = $0 }
    }

    private var openablePDFURL: URL? {
        guard let record = displayedRecord,
              let url = pdfURL(for: record),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return url
    }

    private var pdfMaterializeKey: String {
        let record = displayedRecord
        let path = record?.attachments.first(where: { $0.kind == "main" })?.path
            ?? record?.attachments.first?.path
            ?? ""
        return "\(citekey ?? "")|\(path)"
    }

    @ViewBuilder
    private func pdfPane(for record: LibraryRecord) -> some View {
        switch pdfAvailability(for: record) {
        case .ready(let url):
            PDFViewer(
                url: url,
                citekey: record.citekey,
                darkMode: pdfDarkMode,
                thumbnailSidebarVisible: thumbnailSidebarVisible
            )
        case .downloadingFromICloud, .unavailable:
            ContentUnavailableView {
                Label("PDF not downloaded", systemImage: "icloud.and.arrow.down")
            } description: {
                Text("This file is stored in iCloud and hasn't synced to this Mac yet. Open it in Finder to trigger a download.")
            } actions: {
                if let url = pdfURL(for: record) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        case .noAttachment:
            ContentUnavailableView(
                "No PDF attached",
                systemImage: "doc",
                description: Text("This record has no PDF attachment.")
            )
        }
    }

    private func pdfAvailability(for record: LibraryRecord) -> LibraryPDFAvailability {
        if let materializedPDF, case .ready = materializedPDF {
            return materializedPDF
        }
        if let url = pdfURL(for: record),
           LibraryPDFMaterializer.isReadablePDF(url) {
            return .ready(url)
        }
        if record.attachments.isEmpty {
            return .noAttachment
        }
        return materializedPDF ?? .unavailable
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
