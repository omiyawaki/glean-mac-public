import XCTest
@testable import GleanMac

final class BacklogDOICopyActionTests: XCTestCase {
    func testPresentationNamesCopyDOICommand() {
        XCTAssertEqual(BacklogDOICopyAction.menuTitle, "Copy DOI")
        XCTAssertEqual(BacklogDOICopyAction.systemImage, "doc.on.doc")
    }

    func testCopyDOIWritesTrimmedDOIForBacklogEntry() {
        let entry = BacklogEntry(
            citekey: "Xu2026Multidecadal",
            doi: " 10.1016/j.aosl.2026.100852 ",
            title: "Multidecadal variability",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )
        var copied: [String] = []
        let action = BacklogDOICopyAction(writeString: { copied.append($0) })

        action.copyDOI(for: entry)

        XCTAssertEqual(copied, ["10.1016/j.aosl.2026.100852"])
    }

    func testCopyDOISkipsEntriesWithoutDOI() {
        let entry = BacklogEntry(
            citekey: "NoDOI2026",
            doi: " ",
            title: "No DOI",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )
        var copied: [String] = []
        let action = BacklogDOICopyAction(writeString: { copied.append($0) })

        action.copyDOI(for: entry)

        XCTAssertTrue(copied.isEmpty)
        XCTAssertFalse(BacklogDOICopyAction.isAvailable(for: entry))
        XCTAssertFalse(BacklogDOICopyAction.isAvailable(for: nil))
    }
}
