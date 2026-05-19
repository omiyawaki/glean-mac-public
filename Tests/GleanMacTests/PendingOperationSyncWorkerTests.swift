import XCTest
@testable import GleanMac

@MainActor
final class PendingOperationSyncWorkerTests: XCTestCase {
    func testSyncSubmitsQueuedOperationAndMarksItSynced() async throws {
        let store = PendingOperationStore(url: tempURL())
        let operation = try await store.enqueue(.reviewAdd(doi: "10.1000/add"))
        var submitted: [PendingOperation.Kind] = []
        let worker = PendingOperationSyncWorker(store: store) { operation in
            submitted.append(operation.kind)
            return .synced
        }

        await worker.syncPending()

        XCTAssertEqual(submitted, [.reviewAdd(doi: "10.1000/add")])
        XCTAssertEqual(store.operations.first?.id, operation.id)
        XCTAssertEqual(store.operations.first?.status, .synced)
    }

    func testSyncRetriesFailedOperation() async throws {
        let store = PendingOperationStore(url: tempURL())
        let operation = try await store.enqueue(.authorFollow(author: "Miyawaki"))
        try await store.markFailed(id: operation.id, message: "offline")
        var submitCount = 0
        let worker = PendingOperationSyncWorker(store: store) { _ in
            submitCount += 1
            return .synced
        }

        await worker.syncPending()

        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(store.operations.first?.status, .synced)
        XCTAssertNil(store.operations.first?.errorMessage)
    }

    func testSyncMarksThrownErrorAsFailed() async throws {
        let store = PendingOperationStore(url: tempURL())
        try await store.enqueue(.reviewSkip(doi: "10.1000/skip"))
        let worker = PendingOperationSyncWorker(store: store) { _ in
            throw URLError(.notConnectedToInternet)
        }

        await worker.syncPending()

        XCTAssertEqual(store.operations.first?.status, .failed)
        XCTAssertNotNil(store.operations.first?.errorMessage)
    }

    func testSyncCanMarkOperationAsNeedsReview() async throws {
        let store = PendingOperationStore(url: tempURL())
        try await store.enqueue(.addPaper(input: "10.1000/conflict",
                                          stagedPDFPath: nil))
        let worker = PendingOperationSyncWorker(store: store) { _ in
            .needsReview("Duplicate DOI")
        }

        await worker.syncPending()

        XCTAssertEqual(store.operations.first?.status, .needsReview)
        XCTAssertEqual(store.operations.first?.errorMessage, "Duplicate DOI")
    }

    func testSyncRequeuesStaleRunningOperationBeforeSubmitting() async throws {
        let store = PendingOperationStore(url: tempURL())
        let operation = try await store.enqueue(.reviewAdd(doi: "10.1000/stale"))
        try await store.markRunning(id: operation.id,
                                    now: Date(timeIntervalSince1970: 0))
        var submitted: [UUID] = []
        let worker = PendingOperationSyncWorker(
            store: store,
            staleRunningInterval: 300,
            now: { Date(timeIntervalSince1970: 1_000) }
        ) { operation in
            submitted.append(operation.id)
            return .synced
        }

        await worker.syncPending()

        XCTAssertEqual(submitted, [operation.id])
        XCTAssertEqual(store.operations.first?.status, .synced)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("operations.json")
    }
}
