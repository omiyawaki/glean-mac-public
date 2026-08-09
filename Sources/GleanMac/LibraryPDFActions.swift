import AppKit
import Foundation

struct LibraryPDFLocator {
    let libraryRoot: URL

    static let `default` = LibraryPDFLocator(
        libraryRoot: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/glean")
    )

    func pdfURL(for record: LibraryRecord) -> URL? {
        let attachment = record.attachments.first(where: { $0.kind == "main" })
            ?? record.attachments.first
        guard let attachment else { return nil }
        return libraryRoot.appendingPathComponent(attachment.path)
    }
}

@MainActor
struct ExternalPDFOpener {
    private let openURL: (URL) -> Bool

    static let system = ExternalPDFOpener { url in
        NSWorkspace.shared.open(url)
    }

    init(openURL: @escaping (URL) -> Bool) {
        self.openURL = openURL
    }

    @discardableResult
    func open(_ url: URL?) -> Bool {
        guard let url else { return false }
        return openURL(url)
    }
}

@MainActor
struct LibraryPaperFileAction {
    static let openPDFMenuTitle = "Open PDF Externally"
    static let revealPDFMenuTitle = "Reveal PDF in Finder"

    typealias LoadRecord = (String) async throws -> LibraryRecord

    private let loadRecord: LoadRecord
    private let locator: LibraryPDFLocator
    private let fileExists: (String) -> Bool
    private let openURL: @MainActor (URL) -> Bool
    private let revealURL: @MainActor (URL) -> Void

    init(
        loadRecord: @escaping LoadRecord = { citekey in
            try await LibraryRecordLoader().load(citekey: citekey)
        },
        locator: LibraryPDFLocator = .default,
        fileExists: @escaping (String) -> Bool = FileManager.default.fileExists,
        openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        revealURL: @escaping @MainActor (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        }
    ) {
        self.loadRecord = loadRecord
        self.locator = locator
        self.fileExists = fileExists
        self.openURL = openURL
        self.revealURL = revealURL
    }

    static func hasKnownPDF(for entry: LibraryEntry, loadedRecord: LibraryRecord?) -> Bool? {
        guard loadedRecord?.citekey == entry.citekey, let loadedRecord else { return nil }
        return LibraryPDFLocator.default.pdfURL(for: loadedRecord) != nil
    }

    func openPDF(
        for entry: LibraryEntry,
        loadedRecord: LibraryRecord?
    ) async throws {
        let url = try await pdfURL(for: entry, loadedRecord: loadedRecord)
        guard fileExists(url.path) else {
            throw ActionError.pdfNotDownloaded
        }
        guard openURL(url) else {
            throw ActionError.openFailed
        }
    }

    func revealPDF(
        for entry: LibraryEntry,
        loadedRecord: LibraryRecord?
    ) async throws {
        let url = try await pdfURL(for: entry, loadedRecord: loadedRecord)
        revealURL(url)
    }

    private func pdfURL(
        for entry: LibraryEntry,
        loadedRecord: LibraryRecord?
    ) async throws -> URL {
        let record: LibraryRecord
        if loadedRecord?.citekey == entry.citekey, let loadedRecord {
            record = loadedRecord
        } else {
            do {
                record = try await loadRecord(entry.citekey)
            } catch {
                throw ActionError.recordUnavailable(error.localizedDescription)
            }
        }
        guard let url = locator.pdfURL(for: record) else {
            throw ActionError.noPDFAttached
        }
        return url
    }

    enum ActionError: LocalizedError, Equatable {
        case recordUnavailable(String)
        case noPDFAttached
        case pdfNotDownloaded
        case openFailed

        var errorDescription: String? {
            switch self {
            case .recordUnavailable(let detail):
                "Couldn't load the paper record: \(detail)"
            case .noPDFAttached:
                "This paper has no PDF attachment."
            case .pdfNotDownloaded:
                "The attached PDF isn't downloaded on this Mac. Try Reveal PDF in Finder to download it from iCloud."
            case .openFailed:
                "The default PDF viewer couldn't open this file."
            }
        }
    }
}
