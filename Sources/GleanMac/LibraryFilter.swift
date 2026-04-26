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

    /// Filter by case-insensitive substring match on title or author
    /// family/given. Empty / whitespace-only query returns the input
    /// unchanged.
    static func filter(_ entries: [LibraryEntry], query: String) -> [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { entry in
            if entry.title.lowercased().contains(q) { return true }
            return entry.authors.contains { author in
                author.family.lowercased().contains(q)
                    || author.given.lowercased().contains(q)
            }
        }
    }

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
