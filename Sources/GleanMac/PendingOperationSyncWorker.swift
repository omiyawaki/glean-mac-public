import Foundation

enum PendingOperationSyncResult: Equatable, Sendable {
    case synced
    case needsReview(String)
}

@MainActor
final class PendingOperationSyncWorker {
    typealias Submit = @MainActor (PendingOperation) async throws -> PendingOperationSyncResult

    private let store: PendingOperationStore
    private let submit: Submit

    init(store: PendingOperationStore,
         submit: @escaping Submit = { try await IntakeActions.submit($0) }) {
        self.store = store
        self.submit = submit
    }

    func syncPending() async {
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
