import XCTest
@testable import GleanMac

final class LibraryCitationActionsTests: XCTestCase {
    func testStyleMenuUsesPublisherNames() {
        XCTAssertEqual(
            LibraryCitationStyle.allCases.map(\.menuTitle),
            ["AMS", "AGU", "EGU / Copernicus", "IOP", "PNAS"]
        )
    }

    func testRecordLoaderHTTPErrorKeepsUsefulDetailMessage() {
        let error = LibraryRecordLoader.LoadError.httpStatus(503)

        XCTAssertEqual(error.localizedDescription, "HTTP 503")
    }

    func testFormatsJournalArticleForEachPublisherStyle() {
        let record = makeRecord()
        let formatter = LibraryCitationFormatter()

        XCTAssertEqual(
            formatter.format(record, style: .ams),
            "Miyawaki, O., T. A. Shaw, and M. J. Webb, 2024: Attention to atmospheric dynamics. J. Climate, 37(4), 123–145, https://doi.org/10.1175/JCLI-D-24-0001.1."
        )
        XCTAssertEqual(
            formatter.format(record, style: .agu),
            "Miyawaki, O., Shaw, T. A., & Webb, M. J. (2024). Attention to atmospheric dynamics. Journal of Climate, 37(4), 123–145. https://doi.org/10.1175/JCLI-D-24-0001.1"
        )
        XCTAssertEqual(
            formatter.format(record, style: .egu),
            "Miyawaki, O., Shaw, T. A., and Webb, M. J.: Attention to atmospheric dynamics, Journal of Climate, 37, 123–145, https://doi.org/10.1175/JCLI-D-24-0001.1, 2024."
        )
        XCTAssertEqual(
            formatter.format(record, style: .iop),
            "Miyawaki O, Shaw T A and Webb M J 2024 Attention to atmospheric dynamics Journal of Climate 37 123–145 (doi: 10.1175/JCLI-D-24-0001.1)"
        )
        XCTAssertEqual(
            formatter.format(record, style: .pnas),
            "Miyawaki O, Shaw TA, Webb MJ (2024) Attention to atmospheric dynamics. Journal of Climate 37(4):123–145. https://doi.org/10.1175/JCLI-D-24-0001.1"
        )
    }

    func testListEntryFallbackStillProducesUsefulCitation() {
        let entry = LibraryEntry(
            citekey: "Miyawaki2024Attention",
            title: "Attention to atmospheric dynamics",
            year: 2024,
            doi: "10.1175/JCLI-D-24-0001.1",
            authors: [LibraryAuthor(family: "Miyawaki", given: "Osamu")]
        )

        XCTAssertEqual(
            LibraryCitationFormatter().format(entry, style: .agu),
            "Miyawaki, O. (2024). Attention to atmospheric dynamics. https://doi.org/10.1175/JCLI-D-24-0001.1"
        )
    }

    @MainActor
    func testCopyActionsWriteBareDOIAndCiteID() {
        let entry = LibraryEntry(
            citekey: "Miyawaki2024Attention",
            title: "Attention",
            year: 2024,
            doi: " https://doi.org/10.1175/JCLI-D-24-0001.1 ",
            authors: []
        )
        var copied: [String] = []
        let action = LibraryCopyAction(writeString: { copied.append($0) })

        action.copyDOI(from: entry)
        action.copyCiteID(from: entry)

        XCTAssertEqual(
            copied,
            ["10.1175/JCLI-D-24-0001.1", "Miyawaki2024Attention"]
        )
    }

    @MainActor
    func testCopyDOIIsDisabledWhenMetadataHasNoDOI() {
        let entry = LibraryEntry(
            citekey: "NoDOI2024",
            title: "No DOI",
            year: 2024,
            doi: " ",
            authors: []
        )
        var copied: [String] = []
        let action = LibraryCopyAction(writeString: { copied.append($0) })

        action.copyDOI(from: entry)

        XCTAssertTrue(copied.isEmpty)
        XCTAssertFalse(LibraryCopyAction.canCopyDOI(from: entry))
        XCTAssertFalse(LibraryCopyAction.canCopyDOI(from: nil))
    }

    @MainActor
    func testCitationCopyUsesAlreadyLoadedMatchingRecord() async {
        let record = makeRecord()
        let entry = LibraryEntry(
            citekey: record.citekey,
            title: record.title,
            year: record.year,
            doi: record.doi,
            authors: record.authors
        )
        var loadCount = 0
        var copied: [String] = []
        let action = LibraryCopyAction(
            loadRecord: { _ in
                loadCount += 1
                return record
            },
            writeString: { copied.append($0) }
        )

        await action.copyCitation(from: entry, loadedRecord: record, style: .ams)

        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(copied[0].contains("J. Climate, 37(4), 123–145"))
    }

    private func makeRecord() -> LibraryRecord {
        LibraryRecord(
            citekey: "Miyawaki2024Attention",
            type: "journal-article",
            title: "Attention to atmospheric dynamics",
            year: 2024,
            doi: "https://doi.org/10.1175/JCLI-D-24-0001.1",
            arxiv: nil,
            isbn: nil,
            pmid: nil,
            pmcid: nil,
            journal: "Journal of Climate",
            volume: "37",
            issue: "4",
            pages: "123–145",
            publisher: "AMS",
            url: nil,
            abstract: nil,
            keywords: [],
            authors: [
                LibraryAuthor(family: "Miyawaki", given: "Osamu"),
                LibraryAuthor(family: "Shaw", given: "Tiffany A."),
                LibraryAuthor(family: "Webb", given: "Mark J."),
            ],
            attachments: [],
            addedAt: nil,
            modifiedAt: nil,
            read: true,
            notes: nil
        )
    }
}
