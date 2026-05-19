import Foundation

enum PendingOperationSyncResult: Equatable, Sendable {
    case synced
    case needsReview(String)
}

@MainActor
final class PendingOperationSyncWorker {
    typealias Submit = @MainActor (PendingOperation) async throws -> PendingOperationSyncResult

    private let store: PendingOperationStore
    private let staleRunningInterval: TimeInterval
    private let now: @MainActor () -> Date
    private let submit: Submit

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
        try? await store.requeueStaleRunningOperations(
            now: now(),
            olderThan: staleRunningInterval
        )
        for operation in store.pendingOperations {
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
