import Foundation

struct LibraryDeleteRequest: Identifiable, Hashable {
    let citekey: String
    let title: String
    let doi: String?
    let sourceBacklogID: String?

    var id: String { citekey }

    var normalizedDOI: String? {
        LibraryDOI.normalized(doi)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? citekey : trimmed
    }

    var backlogIDs: [String] {
        var ids: Set<String> = ["citekey:\(citekey)"]
        if let sourceBacklogID, !sourceBacklogID.isEmpty {
            ids.insert(sourceBacklogID)
        }
        if let doi = normalizedDOI {
            ids.insert(doi)
        }
        return ids.sorted()
    }

    init(citekey: String,
         title: String,
         doi: String?,
         sourceBacklogID: String? = nil) {
        self.citekey = citekey
        self.title = title
        self.doi = doi
        self.sourceBacklogID = sourceBacklogID
    }

    init(entry: BacklogEntry) {
        self.init(
            citekey: entry.citekey,
            title: entry.title,
            doi: entry.doi,
            sourceBacklogID: entry.id
        )
    }

    init(entry: LibraryEntry) {
        self.init(citekey: entry.citekey, title: entry.title, doi: entry.doi)
    }
}

enum LibraryDeleteAction {
    static let menuTitle = "Delete from Library"
    static let systemImage = "trash"
    static let confirmationTitle = "Delete from Library?"
    static let confirmButtonTitle = "Delete"

    static func confirmationMessage(for request: LibraryDeleteRequest?) -> String {
        guard let request else {
            return "This removes the paper from your library, including any attached PDFs."
        }
        return "This removes “\(request.displayTitle)” from your library, including any attached PDFs."
    }
}
