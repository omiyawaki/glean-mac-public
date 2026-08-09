import XCTest
@testable import GleanMac

final class LibraryChronologyTests: XCTestCase {
    func testMarkersUseRepresentedMonthsAndOneMajorYearLabel() {
        let groups = LibraryFilter.groupByYear([
            entry("MayNew", year: 2026, publishedAt: "2026-05-20"),
            entry("MayOld", year: 2026, publishedAt: "2026-05-02"),
            entry("March", year: 2026, publishedAt: "2026-03-15"),
            entry("Pending2026", year: 2026),
            entry("Legacy", year: 2025),
        ])

        let markers = LibraryChronology.markers(for: groups)

        XCTAssertEqual(
            markers.map(\.id),
            ["MayNew", "March", "Pending2026", "Legacy"]
        )
        XCTAssertEqual(
            markers.map(\.label),
            ["May 2026", "March 2026", "2026 (date pending)", "2025"]
        )
        XCTAssertEqual(markers.map(\.majorLabel), ["2026", nil, nil, "2025"])
    }

    func testUndatedGroupHasFallbackDestination() {
        let groups = LibraryFilter.groupByYear([entry("Unknown", year: nil)])
        XCTAssertEqual(
            LibraryChronology.markers(for: groups),
            [.init(id: "Unknown", label: "Undated", majorLabel: "Undated")]
        )
    }

    private func entry(
        _ citekey: String,
        year: Int?,
        publishedAt: String? = nil
    ) -> LibraryEntry {
        LibraryEntry(
            citekey: citekey,
            title: citekey,
            year: year,
            publishedAt: publishedAt,
            doi: nil,
            authors: []
        )
    }
}
