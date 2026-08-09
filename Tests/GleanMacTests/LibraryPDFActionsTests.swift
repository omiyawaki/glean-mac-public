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

    @MainActor
    func testPaperFileActionOpensLoadedPDFWithoutRefetching() async throws {
        let root = URL(fileURLWithPath: "/tmp/glean-library")
        let record = makeRecord(attachments: [
            LibraryAttachment(path: "attachments/main.pdf", kind: "main")
        ])
        let entry = makeEntry()
        var loadCount = 0
        var openedURLs: [URL] = []
        let action = LibraryPaperFileAction(
            loadRecord: { _ in
                loadCount += 1
                return record
            },
            locator: LibraryPDFLocator(libraryRoot: root),
            fileExists: { _ in true },
            openURL: { url in
                openedURLs.append(url)
                return true
            },
            revealURL: { _ in }
        )

        try await action.openPDF(for: entry, loadedRecord: record)

        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(openedURLs, [root.appendingPathComponent("attachments/main.pdf")])
        XCTAssertEqual(
            LibraryPaperFileAction.hasKnownPDF(for: entry, loadedRecord: record),
            true
        )
    }

    @MainActor
    func testPaperFileActionRevealsFetchedPDF() async throws {
        let root = URL(fileURLWithPath: "/tmp/glean-library")
        let record = makeRecord(attachments: [
            LibraryAttachment(path: "attachments/main.pdf", kind: "main")
        ])
        var revealedURLs: [URL] = []
        let action = LibraryPaperFileAction(
            loadRecord: { _ in record },
            locator: LibraryPDFLocator(libraryRoot: root),
            fileExists: { _ in true },
            openURL: { _ in true },
            revealURL: { revealedURLs.append($0) }
        )

        try await action.revealPDF(for: makeEntry(), loadedRecord: nil)

        XCTAssertEqual(revealedURLs, [root.appendingPathComponent("attachments/main.pdf")])
    }

    @MainActor
    func testPaperFileActionReportsMissingAttachment() async {
        let record = makeRecord(attachments: [])
        let action = LibraryPaperFileAction(
            loadRecord: { _ in record },
            locator: LibraryPDFLocator(libraryRoot: URL(fileURLWithPath: "/tmp")),
            fileExists: { _ in true },
            openURL: { _ in true },
            revealURL: { _ in }
        )

        do {
            try await action.openPDF(for: makeEntry(), loadedRecord: record)
            XCTFail("Expected noPDFAttached")
        } catch {
            XCTAssertEqual(error as? LibraryPaperFileAction.ActionError, .noPDFAttached)
        }
        XCTAssertEqual(
            LibraryPaperFileAction.hasKnownPDF(for: makeEntry(), loadedRecord: record),
            false
        )
    }

    private func makeEntry() -> LibraryEntry {
        LibraryEntry(
            citekey: "Test2026Paper",
            title: "A Test Paper",
            year: 2026,
            doi: "10.1000/test",
            authors: []
        )
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
