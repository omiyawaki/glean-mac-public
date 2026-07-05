import AppKit
import Foundation

struct BacklogDOICopyAction {
    static let menuTitle = "Copy DOI"
    static let systemImage = "doc.on.doc"

    let writeString: (String) -> Void

    init(writeString: @escaping (String) -> Void = BacklogDOICopyAction.writeToPasteboard) {
        self.writeString = writeString
    }

    static func isAvailable(for entry: BacklogEntry?) -> Bool {
        copyableDOI(for: entry) != nil
    }

    func copyDOI(for entry: BacklogEntry) {
        guard let doi = Self.copyableDOI(for: entry) else { return }
        writeString(doi)
    }

    private static func copyableDOI(for entry: BacklogEntry?) -> String? {
        let doi = entry?.doi.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return doi.isEmpty ? nil : doi
    }

    private static func writeToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
