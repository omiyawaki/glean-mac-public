import Foundation

enum PendingOperationSyncResult: Equatable, Sendable {
    case synced
    case needsReview(String)
}

enum PendingOperationTerminalState: Equatable, Sendable {
    case synced
    case failed(String)
    case needsReview(String)
}

@MainActor
final class PendingOperationSyncWorker {
    static let missingStagedFileMessage = "The staged PDF is no longer on disk."

    typealias Submit = @MainActor (PendingOperation) async throws -> PendingOperationSyncResult

    private let store: PendingOperationStore
    private let staleRunningInterval: TimeInterval
    private let now: @MainActor () -> Date
    private let submit: Submit
    private var isSyncing = false
    private var needsFollowUpSync = false
    private var syncWaiters: [CheckedContinuation<Void, Never>] = []

    init(store: PendingOperationStore,
         submit: @escaping Submit = { try await IntakeActions.submit($0) }) {
        self.store = store
        self.staleRunningInterval = PendingOperationStore.defaultStaleRunningInterval
        self.now = { Date() }
        self.submit = submit
    }

    init(store: PendingOperationStore,
         staleRunningInterval: TimeInterval,
         now: @escaping @MainActor () -> Date,
         submit: @escaping Submit) {
        self.store = store
        self.staleRunningInterval = staleRunningInterval
        self.now = now
        self.submit = submit
    }

    func syncPending() async {
        if isSyncing {
            needsFollowUpSync = true
            await withCheckedContinuation { continuation in
                syncWaiters.append(continuation)
            }
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            resumeSyncWaiters()
        }

        repeat {
            needsFollowUpSync = false
            await syncPendingOnce()
        } while needsFollowUpSync
    }

    @discardableResult
    func syncUntilTerminal(operationID: UUID) async -> PendingOperationTerminalState {
        await syncPending()
        guard let operation = store.operations.first(where: { $0.id == operationID }) else {
            return .synced
        }
        switch operation.status {
        case .synced:
            return .synced
        case .failed:
            return .failed(operation.errorMessage ?? "Sync failed")
        case .needsReview:
            return .needsReview(operation.errorMessage ?? "Needs review")
        case .queued, .running:
            return .failed("Operation did not finish syncing")
        }
    }

    private func resumeSyncWaiters() {
        let waiters = syncWaiters
        syncWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func syncPendingOnce() async {
        try? await store.requeueStaleRunningOperations(
            now: now(),
            olderThan: staleRunningInterval
        )
        for operation in store.pendingOperations {
            if store.stagedFileMissing(for: operation) {
                try? await store.markNeedsReview(
                    id: operation.id,
                    message: Self.missingStagedFileMessage
                )
                continue
            }
            do {
                try await store.markRunning(id: operation.id)
                switch try await submit(operation) {
                case .synced:
                    try await store.markSynced(id: operation.id)
                case .needsReview(let message):
                    try await store.markNeedsReview(id: operation.id,
                                                   message: message)
                }
            } catch {
                try? await store.markFailed(id: operation.id,
                                            message: error.localizedDescription)
            }
        }
    }
}
