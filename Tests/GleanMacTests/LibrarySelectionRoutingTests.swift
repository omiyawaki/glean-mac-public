import Foundation
import XCTest

final class LibrarySelectionRoutingTests: XCTestCase {
    func testRowSelectionDoesNotImplicitlyDriveTheScrollController() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/GleanMac/LibraryView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("selection = entry.id"))
        XCTAssertFalse(source.contains(".onChange(of: selection)"))
        XCTAssertTrue(source.contains("matchingLoadedRecord(for: entry)"))
        XCTAssertTrue(source.contains("loadedRecord?.citekey == entry.citekey"))
        XCTAssertTrue(source.contains("onSelect: { marker in"))
        XCTAssertTrue(
            source.contains("scrollController.scroll(toContentPosition: contentPosition)")
        )
    }
}
