import AppKit
import PDFKit
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

    @MainActor
    func testThumbnailSplitViewSetsAndClearsDocumentOnMainView() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        let document = PDFDocument()

        view.setDocument(document)

        XCTAssertIdentical(view.pdfView.document, document)
        XCTAssertIdentical(view.thumbnailView.pdfView, view.pdfView)

        view.setDocument(nil)

        XCTAssertNil(view.pdfView.document)
        XCTAssertIdentical(view.thumbnailView.pdfView, view.pdfView)
    }

    @MainActor
    func testColdLoadingUsesNativeIndeterminateLinearProgress() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)

        view.setLoading(true)

        XCTAssertTrue(view.isLoading)
        XCTAssertEqual(view.loadingIndicatorStyle, .bar)
        XCTAssertTrue(view.loadingIndicatorIsIndeterminate)
    }

    @MainActor
    func testRevisitingRecentPDFUsesCachedDocumentWithoutDebounce() async throws {
        let url = try makeImplicitBackgroundPDF()
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        let coordinator = PDFViewer.Coordinator()

        coordinator.load(url: url, darkMode: false, in: view)
        XCTAssertTrue(view.isLoading)
        let firstDocument = try await waitForDocument(in: view)

        coordinator.load(url: nil, darkMode: false, in: view)
        XCTAssertNil(view.pdfView.document)

        let cachedLoadStart = ContinuousClock.now
        coordinator.load(url: url, darkMode: false, in: view)
        let cachedLoadDuration = cachedLoadStart.duration(to: .now)

        XCTAssertIdentical(
            view.pdfView.document,
            firstDocument,
            "A recent PDF should be restored synchronously from Glean's cache."
        )
        XCTAssertFalse(view.isLoading)
        XCTAssertLessThan(
            cachedLoadDuration,
            .milliseconds(50),
            "A cached paper selection should stay below the local-control interaction budget."
        )
    }

    @MainActor
    func testLatencyMetricCompletesWhenMainPagePixelsAreDrawn() async throws {
        let url = try makeImplicitBackgroundPDF()
        let delegate = LatencyPageDelegate()
        let document = try XCTUnwrap(PDFDocument(url: url))
        document.delegate = delegate
        let page = try XCTUnwrap(document.page(at: 0) as? LatencyReportingPDFPage)
        let tracker = LibraryPDFLatencyTracker.shared
        tracker.reset()
        tracker.selectionChanged(to: "measured")
        tracker.expectFirstFrame(citekey: "measured", url: url)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 240,
            height: 240,
            bitsPerComponent: 8,
            bytesPerRow: 240 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        page.draw(with: .mediaBox, to: context)
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(
            tracker.sampleCount,
            0,
            "Offscreen bitmap and thumbnail draws are not visible PDF frames."
        )

        PDFPageDrawReporter.report(
            page,
            renderedRect: page.bounds(for: .mediaBox),
            isBitmapContext: false
        )
        for _ in 0..<20 where tracker.sampleCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(tracker.latestCitekey, "measured")
        XCTAssertEqual(tracker.sampleCount, 1)
        XCTAssertNotNil(tracker.latestMilliseconds)

        tracker.recordStablePDFReveal(documentURL: url)

        XCTAssertEqual(tracker.latestStablePDFCitekey, "measured")
        XCTAssertEqual(tracker.stablePDFSampleCount, 1)
        XCTAssertNotNil(tracker.latestStablePDFMilliseconds)
    }

    func testWarmPreviewPlacementRequiresMatchingViewportDimensions() throws {
        let pageRect = CGRect(x: 12, y: 18, width: 620, height: 826)
        let placement = PDFWarmPreviewPlacement(
            viewportSize: CGSize(width: 800, height: 600),
            pageRect: pageRect
        )

        XCTAssertEqual(
            placement.pageRect(for: CGSize(width: 800, height: 600)),
            pageRect
        )
        XCTAssertNotNil(
            placement.pageRect(for: CGSize(width: 800.4, height: 599.6)),
            "Sub-pixel layout noise should not discard a valid preview."
        )
        XCTAssertNil(
            placement.pageRect(for: CGSize(width: 801, height: 600)),
            "A changed viewport must never reuse stale PDFKit geometry."
        )
        XCTAssertNil(
            placement.pageRect(for: CGSize(width: 1_200, height: 720)),
            "A substantially different viewport must use a stable background."
        )
        XCTAssertTrue(
            placement.matches(
                viewportSize: CGSize(width: 800.4, height: 599.6),
                pageRect: CGRect(x: 12.3, y: 17.8, width: 620.2, height: 826.1)
            )
        )
        XCTAssertFalse(
            placement.matches(
                viewportSize: CGSize(width: 800, height: 600),
                pageRect: CGRect(x: 12, y: 18, width: 618, height: 826)
            )
        )
    }

    func testVisibleRegionCoverageRequiresEveryExpectedPixelRegion() async throws {
        var coverage = PDFVisibleRegionCoverage()
        coverage.reset(expected: [
            0: CGRect(x: 0, y: 0, width: 100, height: 100)
        ])

        coverage.record(
            pageIndex: 0,
            renderedRect: CGRect(x: 0, y: 0, width: 50, height: 100)
        )
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(coverage.isComplete)

        coverage.record(
            pageIndex: 0,
            renderedRect: CGRect(x: 50, y: 0, width: 50, height: 45)
        )
        XCTAssertFalse(
            coverage.isComplete,
            "A bounding-box union must not mistake an uncovered gap for completion."
        )

        coverage.record(
            pageIndex: 0,
            renderedRect: CGRect(x: 50, y: 45, width: 50, height: 55)
        )
        XCTAssertTrue(coverage.isComplete)
    }

    func testDrawRegionUsesDeviceTileWhenClipReportsWholePage() {
        let region = PDFPageDrawReporter.visibleIntersection(
            pageBounds: CGRect(x: 0, y: 0, width: 240, height: 240),
            clipBounds: CGRect(x: 0, y: 0, width: 240, height: 240),
            deviceBounds: CGRect(x: 0, y: 120, width: 120, height: 120)
        )

        XCTAssertEqual(region, CGRect(x: 0, y: 120, width: 120, height: 120))
    }

    @MainActor
    func testPersistentWarmPreviewRoundTripsOffMainCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PDFWarmPreviewDiskCache(
            directory: directory,
            countLimit: 2,
            totalSizeLimit: 1_024 * 1_024
        )
        let context = try makeBitmapContext(width: 24, height: 32)
        context.setFillColor(PDFDarkModePalette.pageBackgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 32))
        let image = NSImage(
            cgImage: try XCTUnwrap(context.makeImage()),
            size: CGSize(width: 24, height: 32)
        )

        let placement = PDFWarmPreviewPlacement(
            viewportSize: CGSize(width: 640, height: 480),
            pageRect: CGRect(x: 10, y: 12, width: 600, height: 430)
        )
        await cache.insert(
            PDFWarmPreview(
                image: image,
                pageIndex: 3,
                placement: placement
            ),
            for: "fixture|dark:true"
        )
        let restored = await cache.preview(for: "fixture|dark:true")
        let restoredImage = try XCTUnwrap(restored?.image)
        let missing = await cache.preview(for: "changed-fixture|dark:true")

        XCTAssertEqual(restored?.pageIndex, 3)
        XCTAssertEqual(restoredImage.size.width, 24, accuracy: 0.1)
        XCTAssertEqual(restoredImage.size.height, 32, accuracy: 0.1)
        XCTAssertEqual(restored?.placement, placement)
        XCTAssertNil(missing)
    }

    @MainActor
    func testDarkTransitionKeepsNativeScrollerVisibleWhilePDFKitSettles() throws {
        let firstURL = try makeMultipageImplicitBackgroundPDF(pageCount: 8)
        let nextURL = try makeMultipageImplicitBackgroundPDF(pageCount: 3)
        let firstDocument = try XCTUnwrap(PDFDocument(url: firstURL))
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.pdfView.autoScales = true
        view.pdfView.displayMode = .singlePageContinuous
        view.pdfView.displayDirection = .vertical
        view.setDocument(firstDocument)
        view.layoutSubtreeIfNeeded()

        let nativeScroller = try XCTUnwrap(view.nativePDFVerticalScroller)
        nativeScroller.doubleValue = 0.35
        nativeScroller.knobProportion = 0.18

        _ = view.prepareForDocument(
            url: nextURL,
            descriptor: PDFFileCacheDescriptor(url: nextURL),
            darkMode: true
        )
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.isTransitionCoverVisible)
        XCTAssertTrue(
            view.isTransitionScrollerVisible,
            "The native scroller bridge must appear with the PDF preview, not after it."
        )
        let nativeFrame = try XCTUnwrap(view.nativePDFScrollerFrame)
        XCTAssertEqual(view.transitionScrollerFrame.minX, nativeFrame.minX, accuracy: 0.5)
        XCTAssertEqual(view.transitionScrollerFrame.width, nativeFrame.width, accuracy: 0.5)
        XCTAssertEqual(view.transitionScrollerValue, 0.35, accuracy: 0.001)
        XCTAssertEqual(view.transitionScrollerKnobProportion, 0.18, accuracy: 0.001)

        view.setDocument(nil, preservingThumbnails: true)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.isTransitionScrollerVisible)
        XCTAssertEqual(
            view.transitionScrollerKnobProportion,
            0.18,
            accuracy: 0.001,
            "Clearing the old PDF must not make its scroller bridge disappear."
        )
    }

    @MainActor
    func testDarkDocumentTransitionKeepsOpaqueDarkCoverUntilTilesSettle() async throws {
        let url = try makeImplicitBackgroundPDF()
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let coordinator = PDFViewer.Coordinator()

        coordinator.load(url: url, darkMode: true, in: view)

        XCTAssertTrue(view.isTransitionCoverVisible)
        XCTAssertTrue(view.isTransitionScrollerVisible)
        XCTAssertTrue(view.isTransitionCoverOpaque)
        XCTAssertEqual(
            view.transitionCoverBackgroundColor,
            PDFDarkModePalette.pageBackgroundColor
        )
        XCTAssertTrue(view.isLoading)

        let document = try await waitForDocument(in: view)
        let page = try XCTUnwrap(document.page(at: 0) as? InvertedPDFPage)
        let context = try makeBitmapContext(width: 240, height: 240)
        page.draw(with: .mediaBox, to: context)
        PDFPageDrawReporter.report(
            page,
            renderedRect: page.bounds(for: .mediaBox),
            isBitmapContext: false
        )
        await Task.yield()

        // The first completed tile must not uncover PDFKit immediately.
        XCTAssertTrue(view.isTransitionCoverVisible)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(
            view.isTransitionCoverVisible,
            "The bridge must span PDFKit's native tile presentation interval."
        )
        XCTAssertTrue(view.isTransitionScrollerVisible)

        for _ in 0..<40 where view.isTransitionCoverVisible {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(view.isTransitionCoverVisible)
        XCTAssertFalse(view.isTransitionScrollerVisible)
        XCTAssertFalse(view.isLoading)
    }

    @MainActor
    func testLargePDFColdLoadStillPublishesPreparedDarkBridge() async throws {
        let url = try makeImplicitBackgroundPDF()
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(
            repeating: 0,
            count: 11 * 1_024 * 1_024
        ))
        try handle.close()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(size, 10 * 1_024 * 1_024)

        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.layoutSubtreeIfNeeded()
        let coordinator = PDFViewer.Coordinator()

        coordinator.load(url: url, darkMode: true, in: view)
        _ = try await waitForDocument(in: view)

        XCTAssertEqual(
            view.latestPresentedTransitionFrameSource,
            .preparedPreview,
            "Total file size must not force a cold load onto a background-only transition."
        )
        XCTAssertTrue(view.transitionCoverHasImage)
    }

    @MainActor
    func testColdDarkLoadPublishesPreparedPreviewBeforeLiveTilesSettle() async throws {
        let url = try makeImplicitBackgroundPDF()
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.layoutSubtreeIfNeeded()
        let coordinator = PDFViewer.Coordinator()

        coordinator.load(
            url: url,
            citekey: "cold-preview",
            darkMode: true,
            in: view
        )
        let document = try await waitForDocument(in: view)

        XCTAssertEqual(
            view.latestPresentedTransitionFrameSource,
            .preparedPreview,
            "A cold dark load should prepare useful page pixels before exposing PDFKit."
        )

        let revisitView = PDFThumbnailSplitView(configuration: .previewLike)
        revisitView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        revisitView.pdfView.autoScales = true
        revisitView.pdfView.displayMode = .singlePageContinuous
        revisitView.pdfView.displayDirection = .vertical
        revisitView.layoutSubtreeIfNeeded()
        let restoredPageIndex = revisitView.prepareForDocument(
            url: url,
            descriptor: PDFFileCacheDescriptor(url: url),
            darkMode: true
        )
        XCTAssertEqual(restoredPageIndex, 0)
        XCTAssertTrue(revisitView.isTransitionCoverVisible)
        XCTAssertTrue(revisitView.isTransitionCoverOpaque)
        XCTAssertTrue(revisitView.transitionCoverHasImage)
        XCTAssertEqual(revisitView.transitionCoverFrameSource, .cachedPreview)

        revisitView.setDocument(document)
        revisitView.layoutSubtreeIfNeeded()
        revisitView.alignTransitionCoverToCurrentPage()

        let coverRect = try XCTUnwrap(revisitView.transitionCoverImageRect)
        let livePageRect = try XCTUnwrap(
            revisitView.currentPDFPageRectInTransitionCover
        )
        XCTAssertEqual(coverRect.minX, livePageRect.minX, accuracy: 0.5)
        XCTAssertEqual(coverRect.minY, livePageRect.minY, accuracy: 0.5)
        XCTAssertEqual(coverRect.width, livePageRect.width, accuracy: 0.5)
        XCTAssertEqual(coverRect.height, livePageRect.height, accuracy: 0.5)
    }

    @MainActor
    func testViewportMismatchWithEvictedDocumentAvoidsResizeTwitchWithinLatencyBudget() async throws {
        let url = try makeImplicitBackgroundPDF()
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.pdfView.autoScales = true
        view.pdfView.displayMode = .singlePageContinuous
        view.pdfView.displayDirection = .vertical
        view.layoutSubtreeIfNeeded()
        let coordinator = PDFViewer.Coordinator()

        coordinator.load(url: url, darkMode: true, in: view)
        _ = try await waitForDocument(in: view)
        view.layoutSubtreeIfNeeded()
        view.alignTransitionCoverToCurrentPage()
        XCTAssertTrue(view.transitionCoverHasImage)

        coordinator.load(url: nil, darkMode: true, in: view)
        PDFViewer.evictPreparedDocumentsForTesting()
        view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 720)
        view.layoutSubtreeIfNeeded()

        let tracker = LibraryPDFLatencyTracker.shared
        tracker.reset()
        tracker.selectionChanged(to: "viewport-mismatch")
        let startedAt = ContinuousClock.now
        coordinator.load(
            url: url,
            citekey: "viewport-mismatch",
            darkMode: true,
            in: view
        )
        let selectionReturnLatency = startedAt.duration(to: .now)

        XCTAssertNil(
            view.pdfView.document,
            "The test must exercise a parsed-document cache miss."
        )
        XCTAssertTrue(view.isTransitionCoverVisible)
        XCTAssertFalse(
            view.transitionCoverHasImage,
            "Mismatched cached geometry must show only the stable dark surface."
        )
        XCTAssertTrue(view.isLoading)
        XCTAssertLessThan(
            selectionReturnLatency,
            .milliseconds(50),
            "A cache miss must never block the selection interaction."
        )

        let document = try await waitForDocument(in: view)
        view.layoutSubtreeIfNeeded()
        let exactPlacementLatency = startedAt.duration(to: .now)
        XCTAssertTrue(view.transitionCoverHasImage)
        let coverRect = try XCTUnwrap(view.transitionCoverImageRect)
        let livePageRect = try XCTUnwrap(
            view.currentPDFPageRectInTransitionCover
        )
        XCTAssertEqual(coverRect.minX, livePageRect.minX, accuracy: 0.5)
        XCTAssertEqual(coverRect.minY, livePageRect.minY, accuracy: 0.5)
        XCTAssertEqual(coverRect.width, livePageRect.width, accuracy: 0.5)
        XCTAssertEqual(coverRect.height, livePageRect.height, accuracy: 0.5)
        XCTAssertLessThan(
            exactPlacementLatency,
            .milliseconds(500),
            "Even the synthetic worst-case reparse should establish exact geometry promptly."
        )

        let page = try XCTUnwrap(document.page(at: 0) as? InvertedPDFPage)
        let context = try makeBitmapContext(width: 240, height: 240)
        page.draw(with: .mediaBox, to: context)
        for _ in 0..<100 where view.isTransitionCoverVisible {
            try await Task.sleep(for: .milliseconds(10))
        }
        let stablePDFLatency = try XCTUnwrap(
            tracker.latestStablePDFMilliseconds
        )
        XCTAssertFalse(view.isTransitionCoverVisible)
        XCTAssertEqual(
            tracker.latestStablePDFCitekey,
            "viewport-mismatch"
        )
        XCTAssertEqual(tracker.stableCachedPreviewSampleCount, 1)
        XCTAssertEqual(
            tracker.stableCachedPreviewP95Milliseconds,
            stablePDFLatency
        )
        XCTAssertLessThan(
            stablePDFLatency,
            750,
            "Selection-to-stable-live-PDF latency exceeded the worst-case budget."
        )
        print(
            "PDF viewport-mismatch benchmark: selection return "
                + "\(selectionReturnLatency), exact preview \(exactPlacementLatency), "
                + String(format: "stable live PDF %.2f ms", stablePDFLatency)
        )
    }

    @MainActor
    func testPDFDocumentCacheInvalidatesWhenFileChanges() async throws {
        let url = try makeImplicitBackgroundPDF()
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        let coordinator = PDFViewer.Coordinator()

        coordinator.load(url: url, darkMode: false, in: view)
        let firstDocument = try await waitForDocument(in: view)
        XCTAssertEqual(firstDocument.pageCount, 1)
        coordinator.load(url: nil, darkMode: false, in: view)

        let replacementURL = try makeMultipageImplicitBackgroundPDF(pageCount: 2)
        try Data(contentsOf: replacementURL).write(to: url, options: .atomic)
        coordinator.load(url: url, darkMode: false, in: view)

        XCTAssertNil(view.pdfView.document)
        XCTAssertTrue(view.isLoading)
        let replacementDocument = try await waitForDocument(in: view)
        XCTAssertNotIdentical(replacementDocument, firstDocument)
        XCTAssertEqual(replacementDocument.pageCount, 2)
    }

    @MainActor
    func testThumbnailSplitViewAppliesPDFBackgroundOnlyToMainPDFView() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        let color = NSColor(calibratedWhite: 0.2, alpha: 1.0)

        view.setPDFBackgroundColor(color)

        XCTAssertEqual(view.pdfView.backgroundColor, color)
        XCTAssertEqual(view.thumbnailView.backgroundColor.alphaComponent, 0)
    }

    @MainActor
    func testThumbnailSplitViewKeepsThumbnailChromeNativeInDarkMode() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)

        view.setThumbnailDarkMode(true)

        XCTAssertNil(view.thumbnailView.layer?.filters)
        XCTAssertEqual(view.thumbnailView.backgroundColor.alphaComponent, 0)
        let backgroundView = view.thumbnailPane.subviews
            .first { $0 is NSVisualEffectView } as? NSVisualEffectView
        XCTAssertEqual(backgroundView?.material, NSVisualEffectView.Material.sidebar)
        XCTAssertEqual(backgroundView?.blendingMode, NSVisualEffectView.BlendingMode.withinWindow)

        view.setThumbnailDarkMode(false)

        XCTAssertNil(view.thumbnailView.layer?.filters)
        XCTAssertEqual(view.thumbnailView.backgroundColor.alphaComponent, 0)
    }

    @MainActor
    func testInvertedPDFPageThumbnailRendersDarkPagePixels() throws {
        let url = try makeImplicitBackgroundPDF()
        let delegate = DarkPageDelegate()
        let document = try XCTUnwrap(PDFDocument(url: url))
        document.delegate = delegate
        let page = try XCTUnwrap(document.page(at: 0) as? InvertedPDFPage)

        let image = page.thumbnail(
            of: CGSize(width: 120, height: 120),
            for: .mediaBox
        )
        let background = try averageGray(
            in: image,
            rect: CGRect(x: 90, y: 90, width: 16, height: 16)
        )
        let brightestPixel = try maximumGray(in: image)

        XCTAssertEqual(background, PDFDarkModePalette.pageBackgroundLevel, accuracy: 0.04)
        XCTAssertGreaterThan(brightestPixel, 0.70)
    }

    @MainActor
    func testPDFThumbnailSidebarUsesDarkPageImagesWithoutInvertingChrome() async throws {
        let url = try makeImplicitBackgroundPDF()
        let delegate = DarkPageDelegate()
        let document = try XCTUnwrap(PDFDocument(url: url))
        document.delegate = delegate
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 500)

        view.setDocument(document)
        view.setThumbnailDarkMode(true)
        view.layoutSubtreeIfNeeded()

        let item = try XCTUnwrap(view.thumbnailView.thumbnailItems.first)
        for _ in 0..<100 where !item.hasRenderedThumbnail {
            try await Task.sleep(for: .milliseconds(10))
        }
        let image = try XCTUnwrap(item.thumbnailImage)
        XCTAssertGreaterThan(item.bounds.width, 0)
        XCTAssertGreaterThan(item.bounds.height, 0)
        let thumbnailBackground = try averageGray(
            in: image,
            rect: CGRect(x: 90, y: 90, width: 12, height: 12)
        )

        XCTAssertEqual(thumbnailBackground, PDFDarkModePalette.pageBackgroundLevel, accuracy: 0.08)
    }

    @MainActor
    func testThumbnailSidebarScalesThumbnailsWhenSidebarWidens() throws {
        let url = try makeImplicitBackgroundPDF()
        let document = try XCTUnwrap(PDFDocument(url: url))
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)

        view.setDocument(document)
        view.layoutSubtreeIfNeeded()
        let defaultItem = try XCTUnwrap(view.thumbnailView.thumbnailItems.first)
        let defaultWidth = defaultItem.bounds.width

        view.splitView.setPosition(540, ofDividerAt: 0)
        view.layoutSubtreeIfNeeded()
        let wideItem = try XCTUnwrap(view.thumbnailView.thumbnailItems.first)

        XCTAssertGreaterThan(wideItem.bounds.width, defaultWidth + 60)
    }

    @MainActor
    func testThumbnailSidebarRendersRetinaImageForWideSidebar() async throws {
        let url = try makeImplicitBackgroundPDF()
        let delegate = DarkPageDelegate()
        let document = try XCTUnwrap(PDFDocument(url: url))
        document.delegate = delegate
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)

        view.setDocument(document)
        view.splitView.setPosition(540, ofDividerAt: 0)
        view.setThumbnailDarkMode(true)
        view.layoutSubtreeIfNeeded()

        let item = try XCTUnwrap(view.thumbnailView.thumbnailItems.first)
        for _ in 0..<100 where !item.hasRenderedThumbnail {
            try await Task.sleep(for: .milliseconds(10))
        }
        let image = try XCTUnwrap(item.thumbnailImage)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let displayWidth = item.bounds.width - 32

        XCTAssertGreaterThanOrEqual(cgImage.width, Int(ceil(displayWidth * 2)))
    }

    @MainActor
    func testThumbnailSidebarResizeKeepsExistingItemsDuringDrag() throws {
        let url = try makeMultipageImplicitBackgroundPDF(pageCount: 6)
        let document = try XCTUnwrap(PDFDocument(url: url))
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)

        view.setDocument(document)
        view.layoutSubtreeIfNeeded()
        let originalItems = view.thumbnailView.thumbnailItems
        let originalImages = try originalItems.map { try XCTUnwrap($0.thumbnailImage) }

        for position in stride(from: 680, through: 540, by: -10) {
            view.splitView.setPosition(CGFloat(position), ofDividerAt: 0)
            view.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(view.thumbnailView.thumbnailItems.count, originalItems.count)
        for (index, item) in view.thumbnailView.thumbnailItems.enumerated() {
            XCTAssertIdentical(item, originalItems[index])
            XCTAssertIdentical(item.thumbnailImage, originalImages[index])
        }
    }

    @MainActor
    func testThumbnailSidebarBuildsPagesIncrementallyWithoutBlockingInitialLoad() async throws {
        CountingPDFPage.drawCount = 0
        let url = try makeMultipageImplicitBackgroundPDF(pageCount: 12)
        let delegate = CountingPageDelegate()
        let document = try XCTUnwrap(PDFDocument(url: url))
        document.delegate = delegate
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)

        view.setDocument(document)
        view.layoutSubtreeIfNeeded()
        view.thumbnailView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            view.thumbnailView.thumbnailItems.count,
            PDFThumbnailSidebarView.initialSynchronousItemCount
        )
        XCTAssertEqual(
            CountingPDFPage.drawCount,
            0,
            "Initial sidebar load must not rasterize any PDF page on the main actor."
        )
        XCTAssertTrue(view.thumbnailView.isDocumentStackFlipped)
        let firstItem = try XCTUnwrap(view.thumbnailView.thumbnailItems.first)
        let initialFirstItemMinY = firstItem.frame.minY

        for _ in 0..<100 where view.thumbnailView.thumbnailItems.count < 12 {
            try await Task.sleep(for: .milliseconds(10))
            view.thumbnailView.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(
            view.thumbnailView.thumbnailItems.count,
            12,
            "The complete thumbnail list should fill in after yielding to the run loop."
        )
        view.thumbnailView.layoutSubtreeIfNeeded()
        XCTAssertEqual(firstItem.frame.minY, initialFirstItemMinY, accuracy: 0.5)
    }

    @MainActor
    func testThumbnailSidebarKeepsCurrentItemsDuringNextDocumentPreparation() throws {
        let url = try makeMultipageImplicitBackgroundPDF(pageCount: 3)
        let document = try XCTUnwrap(PDFDocument(url: url))
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)

        view.setDocument(document)
        view.layoutSubtreeIfNeeded()
        let existingItems = view.thumbnailView.thumbnailItems

        view.setDocument(nil, preservingThumbnails: true)

        XCTAssertNil(view.pdfView.document)
        XCTAssertEqual(view.thumbnailView.thumbnailItems.count, existingItems.count)
        for (index, item) in view.thumbnailView.thumbnailItems.enumerated() {
            XCTAssertIdentical(item, existingItems[index])
        }
    }

    @MainActor
    func testRevisitingPDFRestoresRenderedThumbnailWithoutRedrawingPage() async throws {
        CountingPDFPage.drawCount = 0
        let url = try makeImplicitBackgroundPDF()
        let firstDelegate = CountingPageDelegate()
        let firstDocument = try XCTUnwrap(PDFDocument(url: url))
        firstDocument.delegate = firstDelegate
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 500)

        view.setDocument(firstDocument)
        view.layoutSubtreeIfNeeded()
        let firstItem = try XCTUnwrap(view.thumbnailView.thumbnailItems.first)
        for _ in 0..<100 where !firstItem.hasRenderedThumbnail {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(firstItem.hasRenderedThumbnail)
        let firstDrawCount = CountingPDFPage.drawCount
        XCTAssertGreaterThan(firstDrawCount, 0)
        XCTAssertTrue(firstItem.applyCachedThumbnailIfAvailable(renderScale: 2))

        view.setDocument(nil)
        let secondDelegate = CountingPageDelegate()
        let secondDocument = try XCTUnwrap(PDFDocument(url: url))
        secondDocument.delegate = secondDelegate
        view.setDocument(secondDocument)
        view.layoutSubtreeIfNeeded()

        let restoredItem = try XCTUnwrap(view.thumbnailView.thumbnailItems.first)
        XCTAssertTrue(
            restoredItem.hasRenderedThumbnail,
            "A rendered thumbnail should be restored during item construction."
        )
        XCTAssertEqual(CountingPDFPage.drawCount, firstDrawCount)
    }

    @MainActor
    func testThumbnailSidebarCancelsPendingPageConstructionWhenDocumentChanges() async throws {
        let firstURL = try makeMultipageImplicitBackgroundPDF(pageCount: 40)
        let secondURL = try makeMultipageImplicitBackgroundPDF(pageCount: 2)
        let firstDocument = try XCTUnwrap(PDFDocument(url: firstURL))
        let secondDocument = try XCTUnwrap(PDFDocument(url: secondURL))
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)

        view.setDocument(firstDocument)
        XCTAssertEqual(view.thumbnailView.thumbnailItems.count, 1)

        view.setDocument(secondDocument)
        for _ in 0..<30 where view.thumbnailView.thumbnailItems.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(view.thumbnailView.thumbnailItems.count, 2)
        XCTAssertTrue(
            view.thumbnailView.thumbnailItems.allSatisfy { $0.page.document === secondDocument }
        )
    }

    @MainActor
    func testThumbnailSplitViewDoesNotReloadThumbnailsWhenDarkModeIsUnchanged() throws {
        let url = try makeMultipageImplicitBackgroundPDF(pageCount: 3)
        let document = try XCTUnwrap(PDFDocument(url: url))
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)

        view.setDocument(document)
        view.setThumbnailDarkMode(false)
        let originalItems = view.thumbnailView.thumbnailItems

        view.setThumbnailDarkMode(false)

        XCTAssertEqual(view.thumbnailView.thumbnailItems.count, originalItems.count)
        for (index, item) in view.thumbnailView.thumbnailItems.enumerated() {
            XCTAssertIdentical(item, originalItems[index])
        }
    }

    private final class DarkPageDelegate: NSObject, PDFDocumentDelegate {
        func classForPage() -> AnyClass {
            InvertedPDFPage.self
        }
    }

    private final class CountingPageDelegate: NSObject, PDFDocumentDelegate {
        func classForPage() -> AnyClass {
            CountingPDFPage.self
        }
    }

    private final class LatencyPageDelegate: NSObject, PDFDocumentDelegate {
        func classForPage() -> AnyClass {
            LatencyReportingPDFPage.self
        }
    }

    private final class CountingPDFPage: PDFPage {
        nonisolated(unsafe) static var drawCount = 0

        override func draw(with box: PDFDisplayBox, to context: CGContext) {
            Self.drawCount += 1
            super.draw(with: box, to: context)
        }
    }

    private func makeImplicitBackgroundPDF() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("implicit-background.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 240, height: 240)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            XCTFail("Could not create fixture PDF.")
            return url
        }

        context.beginPDFPage(nil)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 56, y: 56, width: 88, height: 32))
        context.endPDFPage()
        context.closePDF()

        return url
    }

    private func makeMultipageImplicitBackgroundPDF(pageCount: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("multipage-implicit-background.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 240, height: 240)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            XCTFail("Could not create fixture PDF.")
            return url
        }

        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(
                x: 48,
                y: 52 + CGFloat(pageIndex % 4) * 4,
                width: 100,
                height: 32
            ))
            context.endPDFPage()
        }
        context.closePDF()

        return url
    }

    private func makeBitmapContext(width: Int, height: Int) throws -> CGContext {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    @MainActor
    private func waitForDocument(
        in view: PDFThumbnailSplitView,
        attempts: Int = 200
    ) async throws -> PDFDocument {
        for _ in 0..<attempts {
            if let document = view.pdfView.document {
                return document
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(view.pdfView.document, "Timed out waiting for PDF preparation.")
    }

    private func averageGray(in image: NSImage, rect: CGRect) throws -> CGFloat {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try averageGray(in: cgImage, rect: rect)
    }

    private func averageGray(in image: CGImage, rect: CGRect) throws -> CGFloat {
        let width = Int(rect.width)
        let height = Int(rect.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Could not create pixel sampling context.")
            return 0
        }

        context.draw(image, in: CGRect(
            x: -rect.origin.x,
            y: -rect.origin.y,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        ))

        var total: CGFloat = 0
        var count: CGFloat = 0
        var offset = 0
        while offset < pixels.count {
            let red = CGFloat(pixels[offset]) / 255.0
            let green = CGFloat(pixels[offset + 1]) / 255.0
            let blue = CGFloat(pixels[offset + 2]) / 255.0
            total += (red + green + blue) / 3.0
            count += 1
            offset += bytesPerPixel
        }
        return total / count
    }

    private func maximumGray(in image: NSImage) throws -> CGFloat {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Could not create pixel sampling context.")
            return 0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var maximum: CGFloat = 0
        var offset = 0
        while offset < pixels.count {
            let red = CGFloat(pixels[offset]) / 255.0
            let green = CGFloat(pixels[offset + 1]) / 255.0
            let blue = CGFloat(pixels[offset + 2]) / 255.0
            maximum = max(maximum, (red + green + blue) / 3.0)
            offset += bytesPerPixel
        }
        return maximum
    }
}
