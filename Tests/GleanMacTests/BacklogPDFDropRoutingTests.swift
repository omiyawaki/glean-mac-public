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
}
