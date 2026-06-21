import Foundation

@MainActor
struct PDFSourceCleaner {
    var trashItem: (URL) throws -> Void

    static let system = PDFSourceCleaner { url in
        guard url.isFileURL else { return }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    func trashSourcePDF(_ url: URL) {
        try? trashItem(url)
    }
}
