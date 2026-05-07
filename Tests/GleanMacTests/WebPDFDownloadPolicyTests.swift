import XCTest
@testable import GleanMac

final class WebPDFDownloadPolicyTests: XCTestCase {
    func testDetectsPDFByMIMEType() {
        XCTAssertTrue(WebPDFDownloadPolicy.isPDF(
            mimeType: "application/pdf",
            url: URL(string: "https://example.com/article")!
        ))
        XCTAssertTrue(WebPDFDownloadPolicy.isPDF(
            mimeType: "Application/PDF; charset=binary",
            url: URL(string: "https://example.com/article")!
        ))
    }

    func testDetectsPDFByURLWhenMIMETypeIsMissing() {
        XCTAssertTrue(WebPDFDownloadPolicy.isPDF(
            mimeType: nil,
            url: URL(string: "https://example.com/paper.pdf?download=1")!
        ))
    }

    func testDoesNotTreatHTMLAsPDF() {
        XCTAssertFalse(WebPDFDownloadPolicy.isPDF(
            mimeType: "text/html",
            url: URL(string: "https://example.com/paper")!
        ))
    }

    func testDestinationUsesSuggestedFilenameInDownloads() {
        let downloads = URL(filePath: "/tmp/Downloads", directoryHint: .isDirectory)

        let destination = WebPDFDownloadPolicy.destinationURL(
            suggestedFilename: "paper.pdf",
            responseURL: URL(string: "https://example.com/ignored.pdf")!,
            downloadsDirectory: downloads,
            fileExists: { _ in false }
        )

        XCTAssertEqual(destination.path, "/tmp/Downloads/paper.pdf")
    }

    func testDefaultDestinationUsesAppCacheInsteadOfProtectedDownloads() {
        let destination = WebPDFDownloadPolicy.destinationURL(
            suggestedFilename: "paper.pdf",
            responseURL: nil,
            fileExists: { _ in false }
        )

        XCTAssertTrue(destination.path.contains("/Library/Caches/GleanMac/PDF Downloads/"))
        XCTAssertFalse(destination.path.contains("/Downloads/"))
    }

    func testDestinationFallsBackToResponseFilenameAndAvoidsClobbering() {
        let downloads = URL(filePath: "/tmp/Downloads", directoryHint: .isDirectory)

        let destination = WebPDFDownloadPolicy.destinationURL(
            suggestedFilename: nil,
            responseURL: URL(string: "https://example.com/paper.pdf")!,
            downloadsDirectory: downloads,
            fileExists: { $0.lastPathComponent == "paper.pdf" }
        )

        XCTAssertEqual(destination.path, "/tmp/Downloads/paper 2.pdf")
    }

    func testDestinationAppendsPDFExtensionToSuggestedFilename() {
        let downloads = URL(filePath: "/tmp/Downloads", directoryHint: .isDirectory)

        let destination = WebPDFDownloadPolicy.destinationURL(
            suggestedFilename: "article",
            responseURL: URL(string: "https://example.com/download")!,
            downloadsDirectory: downloads,
            fileExists: { _ in false }
        )

        XCTAssertEqual(destination.path, "/tmp/Downloads/article.pdf")
    }

    func testDestinationFallsBackToDefaultFilenameWhenInputsAreEmpty() {
        let downloads = URL(filePath: "/tmp/Downloads", directoryHint: .isDirectory)

        let destination = WebPDFDownloadPolicy.destinationURL(
            suggestedFilename: "",
            responseURL: URL(string: "https://example.com/")!,
            downloadsDirectory: downloads,
            fileExists: { _ in false }
        )

        XCTAssertEqual(destination.path, "/tmp/Downloads/download.pdf")
    }

    func testDestinationFallsBackToDefaultFilenameWhenSuggestedFilenameIsWhitespace() {
        let downloads = URL(filePath: "/tmp/Downloads", directoryHint: .isDirectory)

        let destination = WebPDFDownloadPolicy.destinationURL(
            suggestedFilename: "   \n",
            responseURL: URL(string: "https://example.com/")!,
            downloadsDirectory: downloads,
            fileExists: { _ in false }
        )

        XCTAssertEqual(destination.path, "/tmp/Downloads/download.pdf")
    }
}
