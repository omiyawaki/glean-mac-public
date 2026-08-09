import XCTest
@testable import GleanMac

final class LibraryExportActionsTests: XCTestCase {
    func testNormalizesDOIAndBuildsResolverURL() {
        XCTAssertEqual(
            LibraryDOI.normalized(" https://doi.org/10.1175/JCLI-D-24-0001.1 "),
            "10.1175/JCLI-D-24-0001.1"
        )
        XCTAssertEqual(
            LibraryDOI.url(for: "doi:10.1175/JCLI-D-24-0001.1")?.absoluteString,
            "https://doi.org/10.1175/JCLI-D-24-0001.1"
        )
        XCTAssertNil(LibraryDOI.normalized("  "))
    }

    func testFormatsMarkdownCitationAndDOILink() throws {
        let entry = LibraryEntry(
            citekey: "Miyawaki2024Attention",
            title: "Attention [in] climate",
            year: 2024,
            doi: "10.1175/JCLI-D-24-0001.1",
            authors: []
        )
        let formatter = LibraryMarkdownFormatter()

        XCTAssertEqual(formatter.citation(for: entry), "[@Miyawaki2024Attention]")
        XCTAssertEqual(
            formatter.link(for: entry),
            "[Attention \\[in\\] climate](https://doi.org/10.1175/JCLI-D-24-0001.1)"
        )
    }

    func testFormatsFullBibTeXJournalArticle() {
        let bibTeX = LibraryBibTeXFormatter().format(makeRecord())

        XCTAssertEqual(
            bibTeX,
            """
            @article{Miyawaki2024Attention,
              author = {Miyawaki, Osamu and Shaw, Tiffany A.},
              title = {Attention to climate \\& dynamics},
              journal = {Journal of Climate},
              year = {2024},
              volume = {37},
              number = {4},
              pages = {123–145},
              publisher = {AMS},
              doi = {10.1175/JCLI-D-24-0001.1},
            }
            """
        )
    }

    @MainActor
    func testExportActionsCopyMarkdownAndLoadedRecordBibTeX() async {
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
        let action = LibraryExportAction(
            loadRecord: { _ in
                loadCount += 1
                return record
            },
            writeString: { copied.append($0) }
        )

        action.copyMarkdownCitation(from: entry)
        action.copyMarkdownLink(from: entry)
        await action.copyBibTeX(from: entry, loadedRecord: record)

        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(copied[0], "[@Miyawaki2024Attention]")
        XCTAssertTrue(copied[1].hasPrefix("[Attention to climate & dynamics](https://doi.org/"))
        XCTAssertTrue(copied[2].contains("journal = {Journal of Climate}"))
    }

    @MainActor
    func testExternalDOIActionUsesInjectedWorkspaceHandler() {
        let entry = LibraryEntry(
            citekey: "Miyawaki2024Attention",
            title: "Attention",
            year: 2024,
            doi: "10.1175/JCLI-D-24-0001.1",
            authors: []
        )
        var opened: [URL] = []
        let action = LibraryExternalLinkAction { url in
            opened.append(url)
            return true
        }

        XCTAssertTrue(action.openDOI(from: entry))
        XCTAssertEqual(opened.map(\.absoluteString), ["https://doi.org/10.1175/JCLI-D-24-0001.1"])
        XCTAssertTrue(LibraryExternalLinkAction.canOpenDOI(from: entry))
    }

    private func makeRecord() -> LibraryRecord {
        LibraryRecord(
            citekey: "Miyawaki2024Attention",
            type: "journal-article",
            title: "Attention to climate & dynamics",
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
            ],
            attachments: [],
            addedAt: nil,
            modifiedAt: nil,
            read: true,
            notes: nil
        )
    }
}
