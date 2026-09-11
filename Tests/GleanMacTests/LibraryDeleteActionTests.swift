import XCTest
@testable import GleanMac

final class LibraryDeleteActionTests: XCTestCase {
    func testPresentationCopy() {
        XCTAssertEqual(LibraryDeleteAction.menuTitle, "Delete from Library")
        XCTAssertEqual(LibraryDeleteAction.systemImage, "trash")
        XCTAssertEqual(LibraryDeleteAction.confirmationTitle, "Delete from Library?")
        XCTAssertEqual(LibraryDeleteAction.confirmButtonTitle, "Delete")
    }

    func testConfirmationMessageUsesPaperTitle() {
        let request = LibraryDeleteRequest(
            citekey: "Miyawaki2024Attention",
            title: "Attention and convection",
            doi: "10.1175/JCLI-D-23-0456.1"
        )

        XCTAssertEqual(
            LibraryDeleteAction.confirmationMessage(for: request),
            "This removes “Attention and convection” from your library, including any attached PDFs."
        )
    }

    func testConfirmationMessageFallsBackToCitekeyWhenTitleIsBlank() {
        let request = LibraryDeleteRequest(
            citekey: "List1949Smithsonian",
            title: "  ",
            doi: nil
        )

        XCTAssertEqual(
            LibraryDeleteAction.confirmationMessage(for: request),
            "This removes “List1949Smithsonian” from your library, including any attached PDFs."
        )
    }

    func testBacklogRequestProtectsTheRowIDAndCitekeyFallback() {
        let entry = BacklogEntry(
            citekey: "Xu2026Multidecadal",
            doi: "10.1016/j.aosl.2026.100852",
            title: "Multidecadal variability",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )
        let request = LibraryDeleteRequest(entry: entry)

        XCTAssertEqual(request.citekey, "Xu2026Multidecadal")
        XCTAssertEqual(request.normalizedDOI, "10.1016/j.aosl.2026.100852")
        XCTAssertTrue(request.backlogIDs.contains(entry.id))
        XCTAssertTrue(request.backlogIDs.contains("citekey:Xu2026Multidecadal"))
    }

    func testLibraryRequestIncludesCitekeyBacklogFallback() {
        let entry = LibraryEntry(
            citekey: "List1949Smithsonian",
            title: "Smithsonian Meteorological Tables",
            year: 1949,
            doi: nil,
            authors: []
        )
        let request = LibraryDeleteRequest(entry: entry)

        XCTAssertEqual(request.backlogIDs, ["citekey:List1949Smithsonian"])
        XCTAssertNil(request.normalizedDOI)
    }
}
