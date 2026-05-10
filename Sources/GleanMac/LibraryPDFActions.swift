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
