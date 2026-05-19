import XCTest
@testable import GleanMac

final class SidebarPaneVisibilityTests: XCTestCase {
    func testMountedItemsKeepInitialAndPreviouslySelectedPanes() {
        var mounted = MountedSidebarItems(initial: .backlog)

        mounted.select(.libraryAll)
        mounted.select(.maybeReview)

        XCTAssertTrue(mounted.contains(.backlog))
        XCTAssertTrue(mounted.contains(.libraryAll))
        XCTAssertTrue(mounted.contains(.maybeReview))
        XCTAssertFalse(mounted.contains(.authorProposals))
    }

    func testOnlySelectedPaneIsVisibleAndInteractive() {
        XCTAssertEqual(
            SidebarPaneVisibility.opacity(
                for: .libraryAll,
                selection: .libraryAll
            ),
            1
        )
        XCTAssertEqual(
            SidebarPaneVisibility.opacity(
                for: .backlog,
                selection: .libraryAll
            ),
            0
        )
        XCTAssertTrue(
            SidebarPaneVisibility.allowsHitTesting(
                for: .libraryAll,
                selection: .libraryAll
            )
        )
        XCTAssertFalse(
            SidebarPaneVisibility.allowsHitTesting(
                for: .backlog,
                selection: .libraryAll
            )
        )
    }

    func testSidebarPaneVisibilityChangesDoNotAnimate() {
        XCTAssertNil(SidebarPaneVisibility.selectionAnimation)
    }
}
