import AppKit
import Foundation

enum LibraryDOI {
    static func normalized(_ value: String?) -> String? {
        guard var value = cleaned(value) else { return nil }
        for prefix in ["https://doi.org/", "http://doi.org/", "doi:"] {
            if value.lowercased().hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return value.isEmpty ? nil : value
    }

    static func url(for value: String?) -> URL? {
        guard let doi = normalized(value) else { return nil }
        return URL(string: "https://doi.org/\(doi)")
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

struct LibraryBibTeXFormatter {
    func format(_ entry: LibraryEntry) -> String {
        format(
            citekey: entry.citekey,
            type: "article",
            title: entry.title,
            authors: entry.authors,
            year: entry.year,
            journal: nil,
            volume: nil,
            issue: nil,
            pages: nil,
            publisher: nil,
            doi: entry.doi,
            url: nil,
            isbn: nil,
            arxiv: nil
        )
    }

    func format(_ record: LibraryRecord) -> String {
        format(
            citekey: record.citekey,
            type: bibTeXType(for: record.type),
            title: record.title,
            authors: record.authors,
            year: record.year,
            journal: record.journal,
            volume: record.volume,
            issue: record.issue,
            pages: record.pages,
            publisher: record.publisher,
            doi: record.doi,
            url: record.url,
            isbn: record.isbn,
            arxiv: record.arxiv
        )
    }

    private func format(
        citekey: String,
        type: String,
        title: String,
        authors: [LibraryAuthor],
        year: Int?,
        journal: String?,
        volume: String?,
        issue: String?,
        pages: String?,
        publisher: String?,
        doi: String?,
        url: String?,
        isbn: String?,
        arxiv: String?
    ) -> String {
        var fields: [(String, String?)] = [
            ("author", bibTeXAuthors(authors)),
            ("title", title),
            ("journal", journal),
            ("year", year.map(String.init)),
            ("volume", volume),
            ("number", issue),
            ("pages", pages),
            ("publisher", publisher),
            ("doi", LibraryDOI.normalized(doi)),
            ("url", cleaned(url)),
            ("isbn", cleaned(isbn)),
        ]
        if let arxiv = cleaned(arxiv) {
            fields.append(("eprint", arxiv))
            fields.append(("archivePrefix", "arXiv"))
        }
        let body = fields.compactMap { key, value -> String? in
            guard let value = cleaned(value) else { return nil }
            return "  \(key) = {\(escaped(value))},"
        }.joined(separator: "\n")
        return "@\(type){\(citekey),\n\(body)\n}"
    }

    private func bibTeXType(for type: String?) -> String {
        switch type {
        case "journal-article", "preprint": "article"
        case "book": "book"
        case "chapter": "incollection"
        case "thesis": "phdthesis"
        case "report": "techreport"
        case "conference": "inproceedings"
        default: "misc"
        }
    }

    private func bibTeXAuthors(_ authors: [LibraryAuthor]) -> String? {
        let values = authors.compactMap { author -> String? in
            let family = cleaned(author.family)
            let given = cleaned(author.given)
            switch (family, given) {
            case (.some(let family), .some(let given)):
                return "\(family), \(given)"
            case (.some(let family), .none):
                return family
            case (.none, .some(let given)):
                return given
            case (.none, .none):
                return nil
            }
        }
        return values.isEmpty ? nil : values.joined(separator: " and ")
    }

    private func escaped(_ value: String) -> String {
        var output = ""
        var previousWasEscape = false
        for character in value {
            if ["&", "%", "#", "_", "$"].contains(character), !previousWasEscape {
                output.append("\\")
            }
            output.append(character)
            previousWasEscape = character == "\\" && !previousWasEscape
            if character != "\\" { previousWasEscape = false }
        }
        return output
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

struct LibraryMarkdownFormatter {
    func citation(for entry: LibraryEntry) -> String {
        "[@\(entry.citekey.trimmingCharacters(in: .whitespacesAndNewlines))]"
    }

    func link(for entry: LibraryEntry) -> String? {
        guard let url = LibraryDOI.url(for: entry.doi) else { return nil }
        return "[\(escapedTitle(entry.title))](\(url.absoluteString))"
    }

    private func escapedTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

@MainActor
struct LibraryExportAction {
    static let copyMarkdownCitationMenuTitle = "Copy Markdown Citation"
    static let copyMarkdownLinkMenuTitle = "Copy Markdown Link"
    static let copyBibTeXMenuTitle = "Copy BibTeX"

    typealias LoadRecord = (String) async throws -> LibraryRecord

    private let loadRecord: LoadRecord
    private let writeString: @MainActor (String) -> Void
    private let bibTeXFormatter: LibraryBibTeXFormatter
    private let markdownFormatter: LibraryMarkdownFormatter

    init(
        loadRecord: @escaping LoadRecord = { citekey in
            try await LibraryRecordLoader().load(citekey: citekey)
        },
        writeString: @escaping @MainActor (String) -> Void = LibraryExportAction.writeToPasteboard,
        bibTeXFormatter: LibraryBibTeXFormatter = LibraryBibTeXFormatter(),
        markdownFormatter: LibraryMarkdownFormatter = LibraryMarkdownFormatter()
    ) {
        self.loadRecord = loadRecord
        self.writeString = writeString
        self.bibTeXFormatter = bibTeXFormatter
        self.markdownFormatter = markdownFormatter
    }

    static func canCopyMarkdownLink(from entry: LibraryEntry?) -> Bool {
        LibraryDOI.url(for: entry?.doi) != nil
    }

    func copyMarkdownCitation(from entry: LibraryEntry) {
        writeString(markdownFormatter.citation(for: entry))
    }

    func copyMarkdownLink(from entry: LibraryEntry) {
        guard let link = markdownFormatter.link(for: entry) else { return }
        writeString(link)
    }

    func copyBibTeX(
        from entry: LibraryEntry,
        loadedRecord: LibraryRecord?
    ) async {
        let record: LibraryRecord?
        if loadedRecord?.citekey == entry.citekey {
            record = loadedRecord
        } else {
            record = try? await loadRecord(entry.citekey)
        }
        writeString(record.map(bibTeXFormatter.format) ?? bibTeXFormatter.format(entry))
    }

    private static func writeToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

@MainActor
struct LibraryExternalLinkAction {
    static let openDOIMenuTitle = "Open DOI in Browser"

    private let openURL: @MainActor (URL) -> Bool

    init(openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.openURL = openURL
    }

    static func canOpenDOI(from entry: LibraryEntry?) -> Bool {
        LibraryDOI.url(for: entry?.doi) != nil
    }

    @discardableResult
    func openDOI(from entry: LibraryEntry) -> Bool {
        guard let url = LibraryDOI.url(for: entry.doi) else { return false }
        return openURL(url)
    }
}
