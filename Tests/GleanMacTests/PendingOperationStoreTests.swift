import XCTest
@testable import GleanMac

@MainActor
final class PendingOperationStoreTests: XCTestCase {
    func testEnqueuePersistsOperationAndReloadsIt() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("operations.json")
        let store = PendingOperationStore(url: url)

        let operation = try await store.enqueue(.reviewAdd(doi: "10.1000/test"))
        let reloaded = PendingOperationStore(url: url)
        try await reloaded.load()

        XCTAssertEqual(reloaded.operations.count, 1)
        XCTAssertEqual(reloaded.operations.first?.id, operation.id)
        XCTAssertEqual(reloaded.operations.first?.kind, .reviewAdd(doi: "10.1000/test"))
        XCTAssertEqual(reloaded.operations.first?.status, .queued)
    }

    func testPendingOperationsIncludesQueuedAndFailedButNotSynced() async throws {
        let store = PendingOperationStore(url: tempURL())
        let queued = try await store.enqueue(.reviewSkip(doi: "10.1000/queued"))
        let failed = try await store.enqueue(.authorFollow(author: "Miyawaki"))
        let synced = try await store.enqueue(.authorDismiss(author: "Done"))
        try await store.markFailed(id: failed.id, message: "offline")
        try await store.markSynced(id: synced.id)

        let pendingIDs = store.pendingOperations.map(\.id)

        XCTAssertEqual(pendingIDs, [queued.id, failed.id])
    }

    func testMarkFailedPersistsErrorForRetryAfterRelaunch() async throws {
        let url = tempURL()
        let store = PendingOperationStore(url: url)
        let operation = try await store.enqueue(.addPaper(input: "10.1000/offline",
                                                          stagedPDFPath: nil))

        try await store.markFailed(id: operation.id, message: "Server unavailable")
        let reloaded = PendingOperationStore(url: url)
        try await reloaded.load()

        XCTAssertEqual(reloaded.operations.first?.status, .failed)
        XCTAssertEqual(reloaded.operations.first?.errorMessage, "Server unavailable")
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("operations.json")
    }
}
