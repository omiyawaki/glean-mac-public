import XCTest
@testable import GleanMac

final class SidebarContentChromeTests: XCTestCase {
    func testTitleFollowsSelectedSidebarItem() {
        XCTAssertEqual(SidebarContentChrome.title(for: .libraryAll), "All Papers")
        XCTAssertEqual(SidebarContentChrome.title(for: .backlog), "Backlog")
        XCTAssertEqual(SidebarContentChrome.title(for: .maybeReview), "Maybe Review")
        XCTAssertEqual(SidebarContentChrome.title(for: .authorProposals), "Author Proposals")
        XCTAssertEqual(SidebarContentChrome.title(for: nil), "Select a section")
    }

    func testRefreshIsAvailableOnlyWhenAContentPaneIsSelected() {
        XCTAssertTrue(SidebarContentChrome.isRefreshAvailable(for: .libraryAll))
        XCTAssertTrue(SidebarContentChrome.isRefreshAvailable(for: .backlog))
        XCTAssertTrue(SidebarContentChrome.isRefreshAvailable(for: .maybeReview))
        XCTAssertTrue(SidebarContentChrome.isRefreshAvailable(for: .authorProposals))
        XCTAssertFalse(SidebarContentChrome.isRefreshAvailable(for: nil))
    }

    func testLibrarySubtitleUsesVisibleCountAndRefreshTime() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertEqual(
            SidebarContentChrome.librarySubtitle(
                hasLoadedOnce: false,
                totalCount: 20,
                visibleCount: 12,
                lastRefreshedAt: now,
                now: now
            ),
            ""
        )
        XCTAssertEqual(
            SidebarContentChrome.librarySubtitle(
                hasLoadedOnce: true,
                totalCount: 20,
                visibleCount: 12,
                lastRefreshedAt: now,
                now: now
            ),
            "12 of 20 papers • Updated just now"
        )
    }

    func testIntakeSubtitleUsesSectionSpecificCopy() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertEqual(
            SidebarContentChrome.backlogSubtitle(
                hasLoadedOnce: true,
                count: 1,
                lastRefreshedAt: nil,
                now: now
            ),
            "Global: 1 paper awaiting PDF"
        )
        XCTAssertEqual(
            SidebarContentChrome.maybeReviewSubtitle(
                hasLoadedOnce: true,
                count: 3,
                lastRefreshedAt: now,
                now: now
            ),
            "3 papers to review • Updated just now"
        )
        XCTAssertEqual(
            SidebarContentChrome.authorProposalsSubtitle(
                hasLoadedOnce: false,
                count: 2,
                lastRefreshedAt: now,
                now: now
            ),
            ""
        )
    }
}
