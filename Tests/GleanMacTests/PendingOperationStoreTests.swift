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

    func testEnqueueCoalescesDuplicateAttachPDFForSameCitekey() async throws {
        let pendingPDFDirectory = tempDirectory()
        let firstPDF = pendingPDFDirectory.appendingPathComponent("first.pdf")
        let secondPDF = pendingPDFDirectory.appendingPathComponent("second.pdf")
        try FileManager.default.createDirectory(
            at: pendingPDFDirectory,
            withIntermediateDirectories: true
        )
        try Data("%PDF-1.7\nfirst".utf8).write(to: firstPDF)
        try Data("%PDF-1.7\nsecond".utf8).write(to: secondPDF)
        let store = PendingOperationStore(
            url: tempURL(),
            managedPendingPDFDirectory: pendingPDFDirectory
        )
        let first = try await store.enqueue(
            .attachPDF(stagedFilePath: firstPDF.path,
                       citekey: "Abdi2026Hrrrcast"),
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let second = try await store.enqueue(
            .attachPDF(stagedFilePath: secondPDF.path,
                       citekey: "Abdi2026Hrrrcast"),
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(store.operations.count, 1)
        XCTAssertEqual(
            store.operations.first?.kind,
            .attachPDF(stagedFilePath: firstPDF.path,
                       citekey: "Abdi2026Hrrrcast")
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstPDF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondPDF.path))
    }

    func testEnqueueReplacesFailedDuplicateAttachPDFForSameCitekey() async throws {
        let store = PendingOperationStore(url: tempURL())
        let first = try await store.enqueue(
            .attachPDF(stagedFilePath: "/tmp/failed.pdf",
                       citekey: "Abdi2026Hrrrcast"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await store.markFailed(id: first.id, message: "offline")

        let second = try await store.enqueue(
            .attachPDF(stagedFilePath: "/tmp/fresh.pdf",
                       citekey: "Abdi2026Hrrrcast"),
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(store.operations.count, 1)
        XCTAssertEqual(
            store.operations.first?.kind,
            .attachPDF(stagedFilePath: "/tmp/fresh.pdf",
                       citekey: "Abdi2026Hrrrcast")
        )
        XCTAssertEqual(store.operations.first?.status, .queued)
        XCTAssertNil(store.operations.first?.errorMessage)
    }

    func testMarkSyncedRemovesOperationAndManagedStagedPDF() async throws {
        let pendingPDFDirectory = tempDirectory()
        let stagedPDF = pendingPDFDirectory.appendingPathComponent("staged.pdf")
        try FileManager.default.createDirectory(
            at: pendingPDFDirectory,
            withIntermediateDirectories: true
        )
        try Data("%PDF-1.7\nsynced".utf8).write(to: stagedPDF)
        let store = PendingOperationStore(
            url: tempURL(),
            managedPendingPDFDirectory: pendingPDFDirectory
        )
        let operation = try await store.enqueue(
            .attachPDF(stagedFilePath: stagedPDF.path,
                       citekey: "Abdi2026Hrrrcast")
        )

        try await store.markSynced(id: operation.id)

        XCTAssertTrue(store.operations.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedPDF.path))
    }

    func testLoadCompactsPersistedDuplicateAttachPDFsByCitekey() async throws {
        let url = tempURL()
        let old = PendingOperation(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 100),
            kind: .attachPDF(stagedFilePath: "/tmp/old.pdf",
                             citekey: "Abdi2026Hrrrcast"),
            status: .failed,
            errorMessage: "offline",
            updatedAt: Date(timeIntervalSince1970: 150)
        )
        let fresh = PendingOperation(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: Date(timeIntervalSince1970: 200),
            kind: .attachPDF(stagedFilePath: "/tmp/fresh.pdf",
                             citekey: "Abdi2026Hrrrcast"),
            status: .queued,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode([old, fresh]).write(to: url)
        let store = PendingOperationStore(url: url)

        try await store.load()

        XCTAssertEqual(store.operations.map(\.id), [fresh.id])
    }

    func testRecoverStaleRunningOperationsRequeuesOnlyExpiredRuns() async throws {
        let store = PendingOperationStore(url: tempURL())
        let fresh = try await store.enqueue(.reviewAdd(doi: "10.1000/fresh"),
                                            createdAt: Date(timeIntervalSince1970: 100))
        let stale = try await store.enqueue(.reviewAdd(doi: "10.1000/stale"),
                                            createdAt: Date(timeIntervalSince1970: 100))
        try await store.markRunning(id: fresh.id, now: Date(timeIntervalSince1970: 900))
        try await store.markRunning(id: stale.id, now: Date(timeIntervalSince1970: 0))

        try await store.requeueStaleRunningOperations(
            now: Date(timeIntervalSince1970: 1_000),
            olderThan: 300
        )

        let statuses = Dictionary(uniqueKeysWithValues: store.operations.map { ($0.id, $0.status) })
        XCTAssertEqual(statuses[fresh.id], .running)
        XCTAssertEqual(statuses[stale.id], .queued)
        XCTAssertEqual(store.pendingOperations.map(\.id), [stale.id])
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

    func testAssignAttachTargetKeepsStagedPDFAndQueuesForSync() async throws {
        let url = tempURL()
        let store = PendingOperationStore(url: url)
        let operation = try await store.enqueue(
            .attachPDF(stagedFilePath: "/tmp/staged.pdf", citekey: nil)
        )
        try await store.markNeedsReview(id: operation.id, message: "Choose a paper")

        try await store.assignAttachTarget(
            id: operation.id,
            citekey: "Abdi2026Hrrrcast"
        )

        let reloaded = PendingOperationStore(url: url)
        try await reloaded.load()
        XCTAssertEqual(
            reloaded.operations.first?.kind,
            .attachPDF(stagedFilePath: "/tmp/staged.pdf",
                       citekey: "Abdi2026Hrrrcast")
        )
        XCTAssertEqual(reloaded.operations.first?.status, .queued)
        XCTAssertNil(reloaded.operations.first?.errorMessage)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("operations.json")
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
