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

    func testQueryMatchesAuthorAndYearAcrossFields() {
        let entries = [
            makeEntry(citekey: "a", title: "Cloud feedbacks", year: 2024,
                      authors: [LibraryAuthor(family: "Miyawaki", given: "Osamu")]),
            makeEntry(citekey: "b", title: "Cloud feedbacks", year: 2025,
                      authors: [LibraryAuthor(family: "Miyawaki", given: "Osamu")]),
            makeEntry(citekey: "c", title: "Cloud feedbacks", year: 2024,
                      authors: [LibraryAuthor(family: "Smith", given: "Jane")]),
        ]

        let result = LibraryFilter.filter(entries, query: "Miyawaki 2024")

        XCTAssertEqual(result.map(\.citekey), ["a"])
    }

    func testQueryMatchesAuthorAndPartialTitleTermsAcrossFields() {
        let entries = [
            makeEntry(citekey: "a",
                      title: "Future tropical precipitation extremes",
                      authors: [LibraryAuthor(family: "Miyawaki", given: "Osamu")]),
            makeEntry(citekey: "b",
                      title: "Future tropical precipitation extremes",
                      authors: [LibraryAuthor(family: "Smith", given: "Jane")]),
            makeEntry(citekey: "c",
                      title: "Observed tropical circulation trends",
                      authors: [LibraryAuthor(family: "Miyawaki", given: "Osamu")]),
        ]

        let result = LibraryFilter.filter(entries, query: "miyawaki precip")

        XCTAssertEqual(result.map(\.citekey), ["a"])
    }

    func testQueryMatchesGivenAndFamilyNameTerms() {
        let entries = [
            makeEntry(citekey: "a", title: "Paper one",
                      authors: [LibraryAuthor(family: "Miyawaki", given: "Osamu")]),
            makeEntry(citekey: "b", title: "Paper two",
                      authors: [LibraryAuthor(family: "Miyazaki", given: "Hayao")]),
        ]

        let result = LibraryFilter.filter(entries, query: "Osamu Miyawaki")

        XCTAssertEqual(result.map(\.citekey), ["a"])
    }

    func testQuerySplitsPunctuationAndMatchesIdentifierFields() {
        let entries = [
            makeEntry(citekey: "Miyawaki2024Clouds",
                      title: "Paper one",
                      doi: "10.1000/cloud.2024"),
            makeEntry(citekey: "Smith2024Ocean",
                      title: "Paper two",
                      doi: "10.1000/ocean.2024"),
            makeEntry(citekey: "CloudyOcean2024",
                      title: "Cloud response",
                      doi: "10.1000/ocean.2024"),
        ]

        XCTAssertEqual(
            LibraryFilter.filter(entries, query: "miyawaki, 2024").map(\.citekey),
            ["Miyawaki2024Clouds"]
        )
        XCTAssertEqual(
            LibraryFilter.filter(entries, query: "miyawaki,2024").map(\.citekey),
            ["Miyawaki2024Clouds"]
        )
        XCTAssertEqual(
            LibraryFilter.filter(entries, query: "10.1000/cloud").map(\.citekey),
            ["Miyawaki2024Clouds"]
        )
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

    func testGroupByYearOrdersNewestPublicationsFirstWithinYear() {
        let entries = [
            makeEntry(citekey: "Alpha2026Older", title: "Older", year: 2026,
                      publishedAt: "2026-04-01", addedAt: "2026-06-01"),
            makeEntry(citekey: "Zulu2026Newer", title: "Newer", year: 2026,
                      publishedAt: "2026-05-01", addedAt: "2026-03-01"),
            makeEntry(citekey: "Beta2025Newest", title: "Older year", year: 2025,
                      publishedAt: "2025-12-01", addedAt: "2026-07-01"),
        ]

        let groups = LibraryFilter.groupByYear(entries)

        XCTAssertEqual(groups.map(\.year), [2026, 2025])
        XCTAssertEqual(
            groups[0].entries.map(\.citekey),
            ["Zulu2026Newer", "Alpha2026Older"]
        )
    }

    func testGroupByYearUsesExactPublicationYearAndFallsBackToAddedDate() {
        let entries = [
            makeEntry(citekey: "Online2026", title: "Online", year: 2025,
                      publishedAt: "2026-01-02"),
            makeEntry(citekey: "LegacyOlder", title: "Old", year: 2025,
                      addedAt: "2026-04-01"),
            makeEntry(citekey: "LegacyNewer", title: "New", year: 2025,
                      addedAt: "2026-05-01"),
        ]

        let groups = LibraryFilter.groupByYear(entries)

        XCTAssertEqual(groups.map(\.year), [2026, 2025])
        XCTAssertEqual(
            groups[1].entries.map(\.citekey),
            ["LegacyNewer", "LegacyOlder"]
        )
    }

    func testGroupByYearUsesCitekeyForTiedOrMissingAddedDates() {
        let entries = [
            makeEntry(citekey: "Zulu", title: "Z", addedAt: nil),
            makeEntry(citekey: "Beta", title: "B", addedAt: "2026-05-01"),
            makeEntry(citekey: "Alpha", title: "A", addedAt: "2026-05-01"),
        ]

        let groups = LibraryFilter.groupByYear(entries)

        XCTAssertEqual(groups[0].entries.map(\.citekey), ["Alpha", "Beta", "Zulu"])
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
        let chronology = LibraryChronology.markers(for: groups)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(filtered.count, 5000)
        XCTAssertGreaterThan(groups.count, 0)
        XCTAssertGreaterThan(chronology.count, 0)
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
                           publishedAt: String? = nil,
                           addedAt: String? = nil,
                           doi: String? = nil,
                           authors: [LibraryAuthor] = []) -> LibraryEntry {
        LibraryEntry(citekey: citekey, title: title, year: year,
                     publishedAt: publishedAt, addedAt: addedAt,
                     doi: doi, authors: authors)
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
