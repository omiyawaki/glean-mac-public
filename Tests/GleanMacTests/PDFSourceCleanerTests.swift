import XCTest
@testable import GleanMac

@MainActor
final class PDFSourceCleanerTests: XCTestCase {
    func testCleanerTrashesSourcePDF() {
        let source = URL(filePath: "/tmp/source.pdf")
        var trashed: [URL] = []
        let cleaner = PDFSourceCleaner { url in
            trashed.append(url)
        }

        cleaner.trashSourcePDF(source)

        XCTAssertEqual(trashed, [source])
    }

    func testCleanerIgnoresTrashFailures() {
        let source = URL(filePath: "/tmp/source.pdf")
        let cleaner = PDFSourceCleaner { _ in
            throw CocoaError(.fileWriteNoPermission)
        }

        cleaner.trashSourcePDF(source)
    }
}
