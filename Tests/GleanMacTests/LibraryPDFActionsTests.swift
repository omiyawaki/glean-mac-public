import XCTest
@testable import GleanMac

final class LibraryPDFActionsTests: XCTestCase {

    func testPDFLocatorPrefersMainAttachment() {
        let root = URL(fileURLWithPath: "/tmp/glean-library")
        let record = makeRecord(attachments: [
            LibraryAttachment(path: "attachments/supplement.pdf", kind: "supplement"),
            LibraryAttachment(path: "attachments/main.pdf", kind: "main")
        ])

        let url = LibraryPDFLocator(libraryRoot: root).pdfURL(for: record)

        XCTAssertEqual(url, root.appendingPathComponent("attachments/main.pdf"))
    }

    func testPDFLocatorFallsBackToFirstAttachment() {
        let root = URL(fileURLWithPath: "/tmp/glean-library")
        let record = makeRecord(attachments: [
            LibraryAttachment(path: "attachments/only.pdf", kind: "supplement")
        ])

        let url = LibraryPDFLocator(libraryRoot: root).pdfURL(for: record)

        XCTAssertEqual(url, root.appendingPathComponent("attachments/only.pdf"))
    }

    func testPDFLocatorReturnsNilWhenRecordHasNoAttachments() {
        let root = URL(fileURLWithPath: "/tmp/glean-library")
        let record = makeRecord(attachments: [])

        XCTAssertNil(LibraryPDFLocator(libraryRoot: root).pdfURL(for: record))
    }

    @MainActor
    func testExternalPDFOpenerCallsInjectedSystemHandler() {
        let expectedURL = URL(fileURLWithPath: "/tmp/paper.pdf")
        var openedURLs: [URL] = []
        let opener = ExternalPDFOpener { url in
            openedURLs.append(url)
            return true
        }

        let didOpen = opener.open(expectedURL)

        XCTAssertTrue(didOpen)
        XCTAssertEqual(openedURLs, [expectedURL])
    }

    @MainActor
    func testExternalPDFOpenerDoesNothingWithoutURL() {
        var openedURLs: [URL] = []
        let opener = ExternalPDFOpener { url in
            openedURLs.append(url)
            return true
        }

        let didOpen = opener.open(nil)

        XCTAssertFalse(didOpen)
        XCTAssertEqual(openedURLs, [])
    }

    private func makeRecord(attachments: [LibraryAttachment]) -> LibraryRecord {
        LibraryRecord(
            citekey: "Test2026Paper",
            type: nil,
            title: "A Test Paper",
            year: 2026,
            doi: nil,
            arxiv: nil,
            isbn: nil,
            pmid: nil,
            pmcid: nil,
            journal: nil,
            volume: nil,
            issue: nil,
            pages: nil,
            publisher: nil,
            url: nil,
            abstract: nil,
            keywords: [],
            authors: [],
            attachments: attachments,
            addedAt: nil,
            modifiedAt: nil,
            read: false,
            notes: nil
        )
    }
}
