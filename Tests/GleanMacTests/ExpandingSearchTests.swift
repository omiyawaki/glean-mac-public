import XCTest
@testable import GleanMac

final class ExpandingSearchTests: XCTestCase {
    func testFilteredQueryKeepsSearchExpanded() {
        XCTAssertTrue(
            ExpandingSearchPresentation.shouldExpand(
                for: "Barnes2013Response"
            )
        )
    }

    func testEmptyAndWhitespaceQueriesDoNotRequireExpansion() {
        XCTAssertFalse(ExpandingSearchPresentation.shouldExpand(for: ""))
        XCTAssertFalse(ExpandingSearchPresentation.shouldExpand(for: "  \n"))
    }
}
