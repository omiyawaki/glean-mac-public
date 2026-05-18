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
    func testThumbnailSplitViewAppliesPDFBackgroundOnlyToMainPDFView() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)
        let color = NSColor(calibratedWhite: 0.2, alpha: 1.0)

        view.setPDFBackgroundColor(color)

        XCTAssertEqual(view.pdfView.backgroundColor, color)
        XCTAssertEqual(view.thumbnailView.backgroundColor?.alphaComponent, 0)
    }

    @MainActor
    func testThumbnailSplitViewKeepsThumbnailChromeNativeInDarkMode() {
        let view = PDFThumbnailSplitView(configuration: .previewLike)

        view.setThumbnailDarkMode(true)

        XCTAssertNil(view.thumbnailView.layer?.filters)
        XCTAssertEqual(view.thumbnailView.backgroundColor?.alphaComponent, 0)
        let backgroundView = view.thumbnailPane.subviews
            .first { $0 is NSVisualEffectView } as? NSVisualEffectView
        XCTAssertEqual(backgroundView?.material, NSVisualEffectView.Material.sidebar)
        XCTAssertEqual(backgroundView?.blendingMode, NSVisualEffectView.BlendingMode.withinWindow)

        view.setThumbnailDarkMode(false)

        XCTAssertNil(view.thumbnailView.layer?.filters)
        XCTAssertEqual(view.thumbnailView.backgroundColor?.alphaComponent, 0)
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

    private final class DarkPageDelegate: NSObject, PDFDocumentDelegate {
        func classForPage() -> AnyClass {
            InvertedPDFPage.self
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

    private func averageGray(in image: NSImage, rect: CGRect) throws -> CGFloat {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
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

        context.draw(cgImage, in: CGRect(
            x: -rect.origin.x,
            y: -rect.origin.y,
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
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
