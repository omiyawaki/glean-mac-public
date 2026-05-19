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

    func testLaunchSelectionPrefersFirstNonEmptyIntakePane() {
        XCTAssertEqual(
            SidebarLaunchSelection.preferredItem(
                backlog: .loaded(count: 2),
                review: .loaded(count: 3),
                authors: .loaded(count: 4)
            ),
            .backlog
        )
        XCTAssertEqual(
            SidebarLaunchSelection.preferredItem(
                backlog: .loaded(count: 0),
                review: .loaded(count: 3),
                authors: .loaded(count: 4)
            ),
            .maybeReview
        )
        XCTAssertEqual(
            SidebarLaunchSelection.preferredItem(
                backlog: .loaded(count: 0),
                review: .loaded(count: 0),
                authors: .loaded(count: 4)
            ),
            .authorProposals
        )
        XCTAssertEqual(
            SidebarLaunchSelection.preferredItem(
                backlog: .loaded(count: 0),
                review: .loaded(count: 0),
                authors: .loaded(count: 0)
            ),
            .libraryAll
        )
    }

    func testLaunchSelectionStopsAtUnloadedHigherPriorityPane() {
        XCTAssertEqual(
            SidebarLaunchSelection.preferredItem(
                backlog: .loaded(count: 0),
                review: .notLoaded,
                authors: .loaded(count: 2)
            ),
            .maybeReview
        )
    }
}
