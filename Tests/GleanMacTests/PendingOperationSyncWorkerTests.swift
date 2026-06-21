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
        XCTAssertFalse(store.operations.contains { $0.id == operation.id })
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
        XCTAssertTrue(store.operations.isEmpty)
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
        XCTAssertTrue(store.operations.isEmpty)
    }

    func testSyncUntilTerminalSubmitsSpecificQueuedOperation() async throws {
        let store = PendingOperationStore(url: tempURL())
        let operation = try await store.enqueue(.reviewSkip(doi: "10.1000/skip"))
        var submitted: [UUID] = []
        let worker = PendingOperationSyncWorker(store: store) { operation in
            submitted.append(operation.id)
            return .synced
        }

        await worker.syncUntilTerminal(operationID: operation.id)

        XCTAssertEqual(submitted, [operation.id])
        XCTAssertTrue(store.operations.isEmpty)
    }

    func testConcurrentSyncRequestsDoNotSubmitOverlappingOperations() async throws {
        let store = PendingOperationStore(url: tempURL())
        try await store.enqueue(.reviewAdd(doi: "10.1000/one"))
        try await store.enqueue(.reviewAdd(doi: "10.1000/two"))
        var activeSubmissions = 0
        var maximumActiveSubmissions = 0
        var submitCount = 0
        let worker = PendingOperationSyncWorker(store: store) { _ in
            activeSubmissions += 1
            maximumActiveSubmissions = max(
                maximumActiveSubmissions,
                activeSubmissions
            )
            submitCount += 1
            try? await Task.sleep(for: .milliseconds(20))
            activeSubmissions -= 1
            return .synced
        }

        async let first: Void = worker.syncPending()
        async let second: Void = worker.syncPending()
        _ = await (first, second)

        XCTAssertEqual(submitCount, 2)
        XCTAssertEqual(maximumActiveSubmissions, 1)
        XCTAssertTrue(store.operations.isEmpty)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("operations.json")
    }
}
