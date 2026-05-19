import XCTest
@testable import GleanMac

final class LibraryListStateTests: XCTestCase {

    @MainActor
    func testUpdateBuildsGroupsAndVisibleCount() {
        let entries = [
            makeEntry(citekey: "A", title: "Cloud paper", year: 2026),
            makeEntry(citekey: "B", title: "Ocean paper", year: 2025),
            makeEntry(citekey: "C", title: "Cloud dynamics", year: 2025),
        ]
        let state = LibraryListState()

        state.update(entries: entries, query: "cloud")

        XCTAssertEqual(state.visibleCount, 2)
        XCTAssertEqual(state.grouped.map(\.year), [2026, 2025])
        XCTAssertEqual(state.grouped.flatMap(\.entries).map(\.citekey), ["A", "C"])
    }

    @MainActor
    func testRepeatedUpdateWithSameInputsKeepsExistingGroups() {
        var recomputeCount = 0
        let state = LibraryListState { entries, _ in
            recomputeCount += 1
            return LibraryListState.Result(
                visibleCount: entries.count,
                grouped: [LibraryFilter.YearGroup(year: 2026, entries: entries)]
            )
        }
        let entries = [makeEntry(citekey: "A", title: "Cloud paper", year: 2026)]

        state.update(entries: entries, query: "")
        let firstGroups = state.grouped
        state.update(entries: entries, query: "")

        XCTAssertEqual(recomputeCount, 1)
        XCTAssertEqual(state.grouped, firstGroups)
    }

    @MainActor
    func testChangingEntryContentForSameCitekeyRecomputesGroups() {
        var recomputeCount = 0
        let state = LibraryListState { entries, _ in
            recomputeCount += 1
            return LibraryListState.Result(
                visibleCount: entries.count,
                grouped: LibraryFilter.groupByYear(entries)
            )
        }

        state.update(
            entries: [makeEntry(citekey: "A", title: "Old", year: 2025)],
            query: ""
        )
        state.update(
            entries: [makeEntry(citekey: "A", title: "New", year: 2026)],
            query: ""
        )

        XCTAssertEqual(recomputeCount, 2)
        XCTAssertEqual(state.grouped.map(\.year), [2026])
    }

    private func makeEntry(
        citekey: String,
        title: String,
        year: Int?,
        authors: [LibraryAuthor] = []
    ) -> LibraryEntry {
        LibraryEntry(
            citekey: citekey,
            title: title,
            year: year,
            doi: nil,
            authors: authors
        )
    }
}
