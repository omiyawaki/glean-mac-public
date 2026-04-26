import XCTest
@testable import GleanMac

final class LibraryFilterTests: XCTestCase {

    // MARK: - filter

    func testEmptyQueryReturnsAllEntries() {
        let entries = makeEntries(count: 5)
        XCTAssertEqual(LibraryFilter.filter(entries, query: "").count, 5)
    }

    func testWhitespaceOnlyQueryReturnsAllEntries() {
        let entries = makeEntries(count: 5)
        XCTAssertEqual(LibraryFilter.filter(entries, query: "   \n").count, 5)
    }

    func testQueryMatchesTitleSubstring() {
        let entries = [
            makeEntry(citekey: "a", title: "Convective gravity waves over the tropics"),
            makeEntry(citekey: "b", title: "Sea-ice loss in the Arctic"),
        ]
        let result = LibraryFilter.filter(entries, query: "gravity")
        XCTAssertEqual(result.map(\.citekey), ["a"])
    }

    func testQueryMatchesAuthorFamily() {
        let entries = [
            makeEntry(citekey: "a", title: "Paper one",
                      authors: [LibraryAuthor(family: "Miyawaki", given: "Osamu")]),
            makeEntry(citekey: "b", title: "Paper two",
                      authors: [LibraryAuthor(family: "Smith", given: "Jane")]),
        ]
        let result = LibraryFilter.filter(entries, query: "miyawaki")
        XCTAssertEqual(result.map(\.citekey), ["a"])
    }

    func testQueryMatchesAuthorGiven() {
        let entries = [
            makeEntry(citekey: "a", title: "Paper one",
                      authors: [LibraryAuthor(family: "Smith", given: "Osamu")]),
            makeEntry(citekey: "b", title: "Paper two",
                      authors: [LibraryAuthor(family: "Doe", given: "Alice")]),
        ]
        let result = LibraryFilter.filter(entries, query: "OSAMU")
        XCTAssertEqual(result.map(\.citekey), ["a"])
    }

    func testQueryIsCaseInsensitive() {
        let entries = [
            makeEntry(citekey: "a", title: "ARCTIC OSCILLATION DYNAMICS"),
        ]
        XCTAssertEqual(LibraryFilter.filter(entries, query: "arctic").count, 1)
        XCTAssertEqual(LibraryFilter.filter(entries, query: "Arctic").count, 1)
        XCTAssertEqual(LibraryFilter.filter(entries, query: "ARCTIC").count, 1)
    }

    // MARK: - groupByYear

    func testGroupByYearDescending() {
        let entries = [
            makeEntry(citekey: "a", title: "p", year: 2024),
            makeEntry(citekey: "b", title: "p", year: 2026),
            makeEntry(citekey: "c", title: "p", year: 2025),
        ]
        let groups = LibraryFilter.groupByYear(entries)
        XCTAssertEqual(groups.map(\.year), [2026, 2025, 2024])
    }

    func testGroupByYearPlacesUndatedLast() {
        let entries = [
            makeEntry(citekey: "a", title: "p", year: 2024),
            makeEntry(citekey: "b", title: "p", year: nil),
            makeEntry(citekey: "c", title: "p", year: 2025),
        ]
        let groups = LibraryFilter.groupByYear(entries)
        XCTAssertEqual(groups.map(\.year), [2025, 2024, nil])
    }

    func testGroupByYearPreservesEntriesPerSection() {
        let entries = [
            makeEntry(citekey: "a", title: "p", year: 2024),
            makeEntry(citekey: "b", title: "p", year: 2024),
            makeEntry(citekey: "c", title: "p", year: 2025),
        ]
        let groups = LibraryFilter.groupByYear(entries)
        XCTAssertEqual(groups[0].year, 2025)
        XCTAssertEqual(groups[0].entries.count, 1)
        XCTAssertEqual(groups[1].year, 2024)
        XCTAssertEqual(groups[1].entries.count, 2)
    }

    // MARK: - performance regression

    /// Reproduces the path that beach-balled the UI: a 5000-record
    /// library, filter by a query that matches a few rows, then
    /// clear the filter (the empty-query path returns ALL rows and
    /// the group has to rebuild from scratch).
    func testFilterAndGroupCompletesUnder100msFor5000Records() {
        let entries = makeEntries(count: 5000)

        let start = Date()
        let filtered = LibraryFilter.filter(entries, query: "")
        let groups = LibraryFilter.groupByYear(filtered)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(filtered.count, 5000)
        XCTAssertGreaterThan(groups.count, 0)
        XCTAssertLessThan(elapsed, 0.1,
                          "filter+group on 5000 records took \(elapsed)s — should be well under 100ms; if this fails the search-clear UI will beach-ball")
    }

    func testFilterMatchingFewRowsAlsoFastAt5000() {
        let entries = makeEntries(count: 5000)

        let start = Date()
        let filtered = LibraryFilter.filter(entries, query: "miyawaki-only-author-2500")
        _ = LibraryFilter.groupByYear(filtered)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(filtered.count, 0,
                             "fixture should produce at least one match for the test author")
        XCTAssertLessThan(elapsed, 0.1,
                          "filter+group on 5000 records took \(elapsed)s")
    }

    // MARK: - fixtures

    private func makeEntry(citekey: String,
                           title: String,
                           year: Int? = 2024,
                           authors: [LibraryAuthor] = []) -> LibraryEntry {
        LibraryEntry(citekey: citekey, title: title, year: year,
                     doi: nil, authors: authors)
    }

    private func makeEntries(count: Int) -> [LibraryEntry] {
        (0..<count).map { i in
            let yearOffset = i % 30
            let year = 2026 - yearOffset
            let isMiyawakiOnly = (i == 2500)
            let authors: [LibraryAuthor]
            if isMiyawakiOnly {
                authors = [LibraryAuthor(family: "miyawaki-only-author-2500",
                                         given: "Osamu")]
            } else {
                authors = [LibraryAuthor(family: "Smith\(i % 200)",
                                         given: "Jane")]
            }
            return LibraryEntry(
                citekey: "Entry\(i)",
                title: "Paper \(i): some general topic in atmospheric dynamics",
                year: year,
                doi: "10.1000/test.\(i)",
                authors: authors
            )
        }
    }
}
