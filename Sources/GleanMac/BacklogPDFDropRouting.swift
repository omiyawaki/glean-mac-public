import Foundation

enum BacklogPDFDropRouting {
    static func pdfURLs(from urls: [URL]) -> [URL] {
        urls.filter { $0.pathExtension.lowercased() == "pdf" }
    }

    static func forceAttachCitekey(for entry: BacklogEntry?) -> String? {
        guard let citekey = entry?.citekey,
              !citekey.isEmpty
        else { return nil }
        return citekey
    }
}
