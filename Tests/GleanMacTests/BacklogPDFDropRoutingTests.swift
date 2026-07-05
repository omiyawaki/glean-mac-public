import XCTest
@testable import GleanMac

final class BacklogPDFDropRoutingTests: XCTestCase {
    func testSelectedDOILessEntryRoutesDropsToItsCitekey() {
        let entry = BacklogEntry(
            citekey: "Andrews1987Middle",
            doi: "",
            title: "Middle Atmosphere Dynamics",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )

        XCTAssertEqual(
            BacklogPDFDropRouting.forceAttachCitekey(for: entry),
            "Andrews1987Middle"
        )
    }

    func testLibraryEntryRoutesDropsToItsCitekey() {
        let entry = LibraryEntry(
            citekey: "Andrews1987Middle",
            title: "Middle Atmosphere Dynamics",
            year: 1987,
            doi: nil,
            authors: []
        )

        XCTAssertEqual(
            BacklogPDFDropRouting.forceAttachCitekey(for: entry),
            "Andrews1987Middle"
        )
    }

    func testLibraryRecordRoutesDropsToItsCitekey() {
        let record = LibraryRecord(
            citekey: "Andrews1987Middle",
            type: "book",
            title: "Middle Atmosphere Dynamics",
            year: 1987,
            doi: nil,
            arxiv: nil,
            isbn: "9780120585762",
            pmid: nil,
            pmcid: nil,
            journal: nil,
            volume: nil,
            issue: nil,
            pages: nil,
            publisher: "Academic Press",
            url: nil,
            abstract: nil,
            keywords: [],
            authors: [],
            attachments: [],
            addedAt: nil,
            modifiedAt: nil,
            read: false,
            notes: nil
        )

        XCTAssertEqual(
            BacklogPDFDropRouting.forceAttachCitekey(for: record),
            "Andrews1987Middle"
        )
    }
}
