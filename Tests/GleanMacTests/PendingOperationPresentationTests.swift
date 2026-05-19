import XCTest
@testable import GleanMac

final class PendingOperationPresentationTests: XCTestCase {
    func testRowsDescribeQueuedAddPaperOperation() {
        let operation = PendingOperation(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            kind: .addPaper(input: "10.1000/test", stagedPDFPath: nil),
            status: .queued,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let row = PendingOperationPresentation.row(for: operation)

        XCTAssertEqual(row.title, "Add paper")
        XCTAssertEqual(row.detail, "10.1000/test")
        XCTAssertEqual(row.statusText, "Waiting to sync")
        XCTAssertEqual(row.systemImage, "doc.badge.plus")
    }

    func testRowsDescribeUnmatchedPDFAsNeedsTarget() {
        let operation = PendingOperation(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            kind: .attachPDF(stagedFilePath: "/tmp/paper.pdf", citekey: nil),
            status: .queued,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let row = PendingOperationPresentation.row(for: operation)

        XCTAssertEqual(row.title, "Match PDF")
        XCTAssertEqual(row.detail, "paper.pdf")
        XCTAssertEqual(row.systemImage, "doc.viewfinder")
        XCTAssertTrue(row.canChooseTarget)
    }

    func testAttentionCountIncludesFailedAndNeedsReview() {
        let operations = [
            makeOperation(status: .queued),
            makeOperation(status: .failed),
            makeOperation(status: .needsReview),
            makeOperation(status: .synced),
        ]

        XCTAssertEqual(
            PendingOperationPresentation.attentionCount(for: operations),
            2
        )
    }

    private func makeOperation(status: PendingOperation.Status) -> PendingOperation {
        PendingOperation(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            kind: .reviewAdd(doi: "10.1000/test"),
            status: status,
            errorMessage: status == .failed ? "offline" : nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
