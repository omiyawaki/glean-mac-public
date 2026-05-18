import AppKit
import XCTest
@testable import GleanMac

final class PDFViewerTests: XCTestCase {

    func testThumbnailSidebarConfigurationUsesPreviewLikeDefaults() {
        let configuration = PDFThumbnailSidebarConfiguration.previewLike

        XCTAssertEqual(configuration.defaultWidth, 160)
        XCTAssertEqual(configuration.minimumWidth, 120)
        XCTAssertEqual(configuration.maximumWidth, 260)
        XCTAssertEqual(configuration.thumbnailSize, CGSize(width: 96, height: 128))
    }

    @MainActor
    func testThumbnailSplitViewPairsThumbnailViewToMainPDFView() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)

        XCTAssertIdentical(view.thumbnailView.pdfView, view.pdfView)
        XCTAssertFalse(view.thumbnailView.allowsDragging)
        XCTAssertFalse(view.thumbnailView.allowsMultipleSelection)
        XCTAssertEqual(view.thumbnailView.maximumNumberOfColumns, 1)
        XCTAssertEqual(view.thumbnailView.thumbnailSize, CGSize(width: 96, height: 128))
    }

    @MainActor
    func testThumbnailSplitViewShowsSidebarByDefaultAndCanToggleIt() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)

        XCTAssertTrue(view.isThumbnailSidebarVisible)
        XCTAssertFalse(view.thumbnailPane.isHidden)

        view.setThumbnailSidebarVisible(false)

        XCTAssertFalse(view.isThumbnailSidebarVisible)
        XCTAssertTrue(view.thumbnailPane.isHidden)

        view.setThumbnailSidebarVisible(true)

        XCTAssertTrue(view.isThumbnailSidebarVisible)
        XCTAssertFalse(view.thumbnailPane.isHidden)
    }

    @MainActor
    func testThumbnailSplitViewConstrainsDividerToConfiguredSidebarWidthRange() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.layoutSubtreeIfNeeded()

        let minCoordinate = view.splitView(
            view.splitView,
            constrainMinCoordinate: 0,
            ofSubviewAt: 0
        )
        let maxCoordinate = view.splitView(
            view.splitView,
            constrainMaxCoordinate: 800,
            ofSubviewAt: 0
        )

        XCTAssertEqual(minCoordinate, 540)
        XCTAssertEqual(maxCoordinate, 680)
    }
}
