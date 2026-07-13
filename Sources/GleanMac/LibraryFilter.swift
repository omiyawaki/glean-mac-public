import Foundation

/// Pure-logic filter and year-grouping for the library list. Extracted
/// from LibraryView so it's testable in isolation — the perf-sensitive
/// path (clearing a non-empty filter on a 5000-record library) is
/// guarded by tests in Tests/GleanMacTests/LibraryFilterTests.swift.
enum LibraryFilter {
    struct YearGroup: Equatable {
        let year: Int?
        let entries: [LibraryEntry]
    }

    /// Filter by normalized terms across title, author names, year,
    /// citekey, and DOI. Empty / whitespace-only query returns the input
    /// unchanged.
    static func filter(_ entries: [LibraryEntry], query: String) -> [LibraryEntry] {
        let terms = searchTerms(for: query)
        guard !terms.isEmpty else { return entries }
        return entries.filter { matches($0, terms: terms) }
    }

    private static func searchTerms(for query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: termSeparators)
            .compactMap { rawTerm in
                let value = rawTerm.trimmingCharacters(in: termBoundaryCharacters)
                return value.isEmpty ? nil : value
            }
    }

    private static func matches(_ entry: LibraryEntry, terms: [String]) -> Bool {
        terms.allSatisfy { term in
            if contains(entry.citekey, term) { return true }
            if contains(entry.title, term) { return true }
            if let year = entry.year, String(year).contains(term) { return true }
            if let doi = entry.doi, contains(doi, term) { return true }
            return entry.authors.contains { author in
                contains(author.family, term) || contains(author.given, term)
            }
        }
    }

    private static func contains(_ value: String, _ term: String) -> Bool {
        value.lowercased().contains(term)
    }

    private static let termSeparators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ",;"))
    private static let termBoundaryCharacters = CharacterSet.alphanumerics.inverted

    /// Group entries by year, descending. Undated entries trail.
    static func groupByYear(_ entries: [LibraryEntry]) -> [YearGroup] {
        var byYear: [Int?: [LibraryEntry]] = [:]
        byYear.reserveCapacity(120)
        for e in entries {
            byYear[e.year, default: []].append(e)
        }
        return byYear.keys.sorted { (a, b) in
            switch (a, b) {
            case (nil, _): return false        // undated last
            case (_, nil): return true
            case (let x?, let y?): return x > y
            default: return false
            }
        }
        .map { YearGroup(year: $0, entries: byYear[$0] ?? []) }
    }
}
