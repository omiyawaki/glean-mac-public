import AppKit
import Foundation

enum LibraryCitationStyle: String, CaseIterable, Identifiable {
    case ams
    case agu
    case egu
    case iop
    case pnas

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .ams: "AMS"
        case .agu: "AGU"
        case .egu: "EGU / Copernicus"
        case .iop: "IOP"
        case .pnas: "PNAS"
        }
    }
}

struct LibraryCitationFormatter {
    func format(_ entry: LibraryEntry, style: LibraryCitationStyle) -> String {
        format(CitationMetadata(entry: entry), style: style)
    }

    func format(_ record: LibraryRecord, style: LibraryCitationStyle) -> String {
        format(CitationMetadata(record: record), style: style)
    }

    private func format(
        _ metadata: CitationMetadata,
        style: LibraryCitationStyle
    ) -> String {
        switch style {
        case .ams:
            formatAMS(metadata)
        case .agu:
            formatAGU(metadata)
        case .egu:
            formatEGU(metadata)
        case .iop:
            formatIOP(metadata)
        case .pnas:
            formatPNAS(metadata)
        }
    }

    private func formatAMS(_ metadata: CitationMetadata) -> String {
        let authorYear = joined(
            [amsAuthors(metadata.authors), metadata.year.map(String.init)],
            separator: ", "
        )
        let heading = authorYear.isEmpty ? "" : "\(authorYear):"
        let publication = joined(
            [amsJournalTitle(metadata.journal),
             volumeAndIssue(metadata),
             metadata.pages,
             metadata.doiURL],
            separator: ", "
        )
        return joined(
            [heading, sentence(metadata.title), sentence(publication)],
            separator: " "
        )
    }

    private func formatAGU(_ metadata: CitationMetadata) -> String {
        let authors = aguAuthors(metadata.authors)
        let year = metadata.year.map { "(\($0))." } ?? ""
        let journalAndVolume = joined(
            [metadata.journal, volumeAndIssue(metadata)],
            separator: ", "
        )
        let publication = joined(
            [journalAndVolume, metadata.pages],
            separator: ", "
        )
        return joined(
            [authors, year, sentence(metadata.title), sentence(publication), metadata.doiURL],
            separator: " "
        )
    }

    private func formatEGU(_ metadata: CitationMetadata) -> String {
        let authors = eguAuthors(metadata.authors)
        let heading = authors.isEmpty ? "" : "\(authors):"
        let year = metadata.year.map(String.init)
        let publication = joined(
            [metadata.journal, metadata.volume, metadata.pages, metadata.doiURL, year],
            separator: ", "
        )
        return joined(
            [heading, commaTerminated(metadata.title), sentence(publication)],
            separator: " "
        )
    }

    private func formatIOP(_ metadata: CitationMetadata) -> String {
        let doi = metadata.doi.map { "(doi: \($0))" }
        return joined(
            [
                iopAuthors(metadata.authors),
                metadata.year.map(String.init),
                metadata.title,
                metadata.journal,
                metadata.volume,
                metadata.pages,
                doi,
            ],
            separator: " "
        )
    }

    private func formatPNAS(_ metadata: CitationMetadata) -> String {
        let year = metadata.year.map { "(\($0))" }
        let publication = pnasPublication(metadata)
        return joined(
            [
                pnasAuthors(metadata.authors),
                year,
                sentence(metadata.title),
                sentence(publication),
                metadata.doiURL,
            ],
            separator: " "
        )
    }

    private func amsAuthors(_ authors: [LibraryAuthor]) -> String {
        guard let first = authors.first else { return "" }
        let firstName = joined([first.family, initials(first.given)], separator: ", ")
        if authors.count >= 9 {
            return "\(firstName), and Coauthors"
        }
        let remaining = authors.dropFirst().map {
            joined([initials($0.given), $0.family], separator: " ")
        }
        return authorList(first: firstName, remaining: remaining, conjunction: "and")
    }

    private func aguAuthors(_ authors: [LibraryAuthor]) -> String {
        let names = authors.map {
            joined([$0.family, initials($0.given)], separator: ", ")
        }
        return authorList(names, conjunction: "&")
    }

    private func eguAuthors(_ authors: [LibraryAuthor]) -> String {
        let names = authors.map {
            joined([$0.family, initials($0.given)], separator: ", ")
        }
        return authorList(names, conjunction: "and")
    }

    private func iopAuthors(_ authors: [LibraryAuthor]) -> String {
        guard authors.count <= 10 else {
            guard let first = authors.first else { return "" }
            return joined([first.family, initials(first.given, periods: false)], separator: " ")
                + " et al"
        }
        let names = authors.map {
            joined([$0.family, initials($0.given, periods: false)], separator: " ")
        }
        return authorList(names, conjunction: "and", serialComma: false)
    }

    private func pnasAuthors(_ authors: [LibraryAuthor]) -> String {
        let visibleAuthors = authors.count >= 10 ? Array(authors.prefix(10)) : authors
        var names = visibleAuthors.map {
            joined([$0.family, compactInitials($0.given)], separator: " ")
        }
        if authors.count >= 10 {
            names.append("et al.")
        }
        return names.joined(separator: ", ")
    }

    private func authorList(
        first: String,
        remaining: [String],
        conjunction: String
    ) -> String {
        guard !remaining.isEmpty else { return first }
        if remaining.count == 1 {
            return "\(first), \(conjunction) \(remaining[0])"
        }
        return "\(first), \(remaining.dropLast().joined(separator: ", ")), \(conjunction) \(remaining.last!)"
    }

    private func authorList(
        _ names: [String],
        conjunction: String,
        serialComma: Bool = true
    ) -> String {
        switch names.count {
        case 0:
            return ""
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) \(conjunction) \(names[1])"
        default:
            let comma = serialComma ? "," : ""
            return "\(names.dropLast().joined(separator: ", "))\(comma) \(conjunction) \(names.last!)"
        }
    }

    private func initials(_ given: String, periods: Bool = true) -> String {
        given
            .split(whereSeparator: { $0.isWhitespace })
            .map { word in
                word.split(separator: "-", omittingEmptySubsequences: true)
                    .compactMap(\.first)
                    .map { periods ? "\($0)." : String($0) }
                    .joined(separator: "-")
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func compactInitials(_ given: String) -> String {
        given
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    private func volumeAndIssue(_ metadata: CitationMetadata) -> String? {
        guard let volume = metadata.volume else { return nil }
        guard let issue = metadata.issue else { return volume }
        return "\(volume)(\(issue))"
    }

    private func amsJournalTitle(_ journal: String?) -> String? {
        guard let journal = cleaned(journal) else { return nil }
        return [
            "Artificial Intelligence for the Earth Systems": "Artif. Intell. Earth Syst.",
            "Bulletin of the American Meteorological Society": "Bull. Amer. Meteor. Soc.",
            "Earth Interactions": "Earth Interact.",
            "Journal of Applied Meteorology and Climatology": "J. Appl. Meteor. Climatol.",
            "Journal of Atmospheric and Oceanic Technology": "J. Atmos. Oceanic Technol.",
            "Journal of Climate": "J. Climate",
            "Journal of Hydrometeorology": "J. Hydrometeor.",
            "Journal of Physical Oceanography": "J. Phys. Oceanogr.",
            "Journal of the Atmospheric Sciences": "J. Atmos. Sci.",
            "Monthly Weather Review": "Mon. Wea. Rev.",
            "Weather and Forecasting": "Wea. Forecasting",
            "Weather, Climate, and Society": "Wea. Climate Soc.",
        ][journal] ?? journal
    }

    private func pnasPublication(_ metadata: CitationMetadata) -> String {
        let journalAndVolume = joined(
            [metadata.journal, volumeAndIssue(metadata)],
            separator: " "
        )
        guard let pages = metadata.pages else { return journalAndVolume }
        return journalAndVolume.isEmpty ? pages : "\(journalAndVolume):\(pages)"
    }

    private func sentence(_ value: String?) -> String {
        guard let value = cleaned(value), !value.isEmpty else { return "" }
        if value.last == "." || value.last == "?" || value.last == "!" {
            return value
        }
        return value + "."
    }

    private func commaTerminated(_ value: String?) -> String {
        guard let value = cleaned(value), !value.isEmpty else { return "" }
        if value.last == "," { return value }
        if value.last == "." { return String(value.dropLast()) + "," }
        return value + ","
    }

    private func joined(_ values: [String?], separator: String) -> String {
        values.compactMap(cleaned).filter { !$0.isEmpty }.joined(separator: separator)
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private struct CitationMetadata {
        let title: String
        let year: Int?
        let doi: String?
        let journal: String?
        let volume: String?
        let issue: String?
        let pages: String?
        let authors: [LibraryAuthor]

        var doiURL: String? {
            doi.map { "https://doi.org/\($0)" }
        }

        init(entry: LibraryEntry) {
            title = entry.title
            year = entry.year
            doi = Self.normalizedDOI(entry.doi)
            journal = nil
            volume = nil
            issue = nil
            pages = nil
            authors = entry.authors
        }

        init(record: LibraryRecord) {
            title = record.title
            year = record.year
            doi = Self.normalizedDOI(record.doi)
            journal = Self.cleaned(record.journal)
            volume = Self.cleaned(record.volume)
            issue = Self.cleaned(record.issue)
            pages = Self.cleaned(record.pages)
            authors = record.authors
        }

        private static func normalizedDOI(_ value: String?) -> String? {
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

        private static func cleaned(_ value: String?) -> String? {
            guard let value else { return nil }
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }
}

@MainActor
struct LibraryCopyAction {
    static let copyDOIMenuTitle = "Copy DOI"
    static let copyCiteIDMenuTitle = "Copy Cite ID"
    static let copyCitationMenuTitle = "Copy Formatted Citation"

    typealias LoadRecord = (String) async throws -> LibraryRecord

    private let loadRecord: LoadRecord
    private let writeString: @MainActor (String) -> Void
    private let formatter: LibraryCitationFormatter

    init(
        loadRecord: @escaping LoadRecord = { citekey in
            try await LibraryRecordLoader().load(citekey: citekey)
        },
        writeString: @escaping @MainActor (String) -> Void = LibraryCopyAction.writeToPasteboard,
        formatter: LibraryCitationFormatter = LibraryCitationFormatter()
    ) {
        self.loadRecord = loadRecord
        self.writeString = writeString
        self.formatter = formatter
    }

    static func canCopyDOI(from entry: LibraryEntry?) -> Bool {
        copyableDOI(from: entry) != nil
    }

    func copyDOI(from entry: LibraryEntry) {
        guard let doi = Self.copyableDOI(from: entry) else { return }
        writeString(doi)
    }

    func copyCiteID(from entry: LibraryEntry) {
        let citekey = entry.citekey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !citekey.isEmpty else { return }
        writeString(citekey)
    }

    func copyCitation(
        from entry: LibraryEntry,
        loadedRecord: LibraryRecord?,
        style: LibraryCitationStyle
    ) async {
        let record: LibraryRecord?
        if loadedRecord?.citekey == entry.citekey {
            record = loadedRecord
        } else {
            record = try? await loadRecord(entry.citekey)
        }
        let citation = record.map { formatter.format($0, style: style) }
            ?? formatter.format(entry, style: style)
        writeString(citation)
    }

    private static func copyableDOI(from entry: LibraryEntry?) -> String? {
        var doi = entry?.doi?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for prefix in ["https://doi.org/", "http://doi.org/", "doi:"] {
            if doi.lowercased().hasPrefix(prefix) {
                doi.removeFirst(prefix.count)
                doi = doi.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return doi.isEmpty ? nil : doi
    }

    private static func writeToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

struct LibraryRecordLoader {
    let endpoints: GleanBackendEndpoints
    let session: URLSession

    init(
        endpoints: GleanBackendEndpoints = .home,
        session: URLSession = .shared
    ) {
        self.endpoints = endpoints
        self.session = session
    }

    func load(citekey: String) async throws -> LibraryRecord {
        var request = URLRequest(url: endpoints.libraryDetailURL(citekey: citekey))
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LoadError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(LibraryRecord.self, from: data)
    }

    enum LoadError: LocalizedError, Equatable {
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let status):
                "HTTP \(status)"
            }
        }
    }
}
