import XCTest
@testable import GleanMac

final class LibraryChronologyTests: XCTestCase {
    func testMarkersUseARegularMonthlyCalendarScale() {
        let groups = LibraryFilter.groupByYear([
            entry("MayNew", year: 2026, publishedAt: "2026-05-20"),
            entry("MayOld", year: 2026, publishedAt: "2026-05-02"),
            entry("March", year: 2026, publishedAt: "2026-03-15"),
            entry("Pending2026", year: 2026),
            entry("Legacy", year: 2025),
        ])

        let layout = LibraryChronology.layout(for: groups)
        let markers = layout.markers

        XCTAssertEqual(markers.count, 17)
        XCTAssertEqual(markers.first?.id, "month:2026-05")
        XCTAssertEqual(markers.first?.label, "May 2026")
        XCTAssertEqual(markers.first?.destinationID, "MayNew")
        XCTAssertEqual(markers[1].label, "April 2026")
        XCTAssertEqual(markers[1].destinationID, "March")
        XCTAssertEqual(markers[4].label, "January 2026")
        XCTAssertEqual(markers[4].destinationID, "Pending2026")
        XCTAssertTrue(markers[4].isYearBoundary)
        XCTAssertEqual(markers[5].label, "December 2025")
        XCTAssertEqual(markers[5].destinationID, "Legacy")
        XCTAssertEqual(markers.last?.label, "January 2025")
        XCTAssertEqual(markers.first?.majorLabel, "2026")
        XCTAssertEqual(markers.last?.majorLabel, "2025")
        XCTAssertEqual(markers.first?.railPosition, 0)
        XCTAssertEqual(markers.last?.railPosition, 1)
        XCTAssertEqual(
            markers.map(\.railPosition),
            markers.map(\.railPosition).sorted()
        )
        XCTAssertEqual(layout.destinationPositions["MayNew"], 0)
        XCTAssertNotNil(layout.destinationPositions["Legacy"])
    }

    func testUndatedGroupHasFallbackDestination() {
        let groups = LibraryFilter.groupByYear([entry("Unknown", year: nil)])
        XCTAssertEqual(
            LibraryChronology.markers(for: groups),
            [
                .init(
                    id: "undated",
                    destinationID: "Unknown",
                    label: "Undated",
                    majorLabel: "Undated",
                    railPosition: 1,
                    contentPosition: 0,
                    isYearBoundary: false
                )
            ]
        )
    }

    func testDecadeLabelsHaveARegularCadenceWithEndpoints() {
        let groups = LibraryFilter.groupByYear([
            entry("Newest", year: 2026, publishedAt: "2026-08-01"),
            entry("Oldest", year: 1998, publishedAt: "1998-04-01"),
        ])

        XCTAssertEqual(
            LibraryChronology.markers(for: groups).compactMap(\.majorLabel),
            ["2026", "2020", "2010", "2000", "1998"]
        )
    }

    func testDensityWeightedScaleExpandsOccupiedMonthsAndCompressesEmptyHistory() throws {
        var entries = [
            entry("Newest", year: 2026, publishedAt: "2026-01-01"),
            entry("Oldest", year: 1900, publishedAt: "1900-01-01"),
        ]
        entries.append(contentsOf: (0..<12).map { index in
            entry("Dense\(index)", year: 2025, publishedAt: "2025-12-15")
        })

        let markers = LibraryChronology.markers(
            for: LibraryFilter.groupByYear(entries)
        )
        let denseMonth = try XCTUnwrap(
            markers.first { $0.id == "month:2025-12" }
        )
        let sparseHistory = try XCTUnwrap(
            markers.first { $0.id == "month:1950-01" }
        )

        XCTAssertGreaterThan(denseMonth.railPosition, 0.25)
        XCTAssertGreaterThan(sparseHistory.railPosition, 0.75)
        XCTAssertEqual(markers.map(\.railPosition), markers.map(\.railPosition).sorted())
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
