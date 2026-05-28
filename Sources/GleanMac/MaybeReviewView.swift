import SwiftUI

struct MaybeReviewView: View {
    let store: ReviewStore
    let actionQueue: ActionQueueStore
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void

    var body: some View {
        Group {
            if !store.hasLoadedOnce {
                if let message = store.lastError {
                    ContentUnavailableView {
                        Label("Couldn't load review queue", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { Task { await store.load() } }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ProgressView().controlSize(.large)
                }
            } else if store.entries.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("The worker auto-decided everything recently.")
                )
            } else {
                List(store.entries) { entry in
                    ReviewRow(
                        entry: entry,
                        onAdd: { perform(.add, entry: entry) },
                        onSkip: { perform(.skip, entry: entry) }
                    )
                }
            }
        }
        .task {
            if !store.hasLoadedOnce { await store.load() }
        }
    }

    private enum Kind {
        case add, skip

        var title: String {
            switch self {
            case .add: "Add paper"
            case .skip: "Skip paper"
            }
        }

        var systemImage: String {
            switch self {
            case .add: "plus.circle"
            case .skip: "archivebox"
            }
        }
    }

    /// Perform an Add or Skip. The optimistic removal + post-mutation
    /// loadAfterLocalMutation pattern (combined with auto-pruning in
    /// IntakeStore.apply) is the root fix for the previous flash-reappear
    /// race and the "stuck hidden on failure" correctness hole.
    @MainActor
    private func perform(_ kind: Kind, entry: ReviewEntry) {
        let id = entry.id
        store.optimisticallyRemove(id: id)
        actionQueue.enqueue(
            title: kind.title,
            detail: entry.title,
            systemImage: kind.systemImage
        ) {
            store.optimisticallyRemove(id: id)
            do {
                switch kind {
                case .add:
                    try await offlineCoordinator.queueReviewAdd(doi: entry.doi)
                case .skip:
                    try await offlineCoordinator.queueReviewSkip(doi: entry.doi)
                }
                await syncPendingOperations()

                // Root fix for the reappearance flash: after the server has
                // committed the removal, immediately load the authoritative
                // state. The apply() auto-pruning will clean up the optimistic
                // guard, and we get the final correct list without waiting
                // for the 0.5 s watcher + SSE roundtrip.
                await store.loadAfterLocalMutation(silent: true)

                // Harmless on success (the prune already did the work), but
                // keeps the call sites consistent and explicit.
                store.releaseOptimisticRemoval(id: id)
            } catch {
                // Failure: the server never removed the entry. Restore
                // visibility immediately so the user can see it and retry
                // via the action queue.
                store.releaseOptimisticRemoval(id: id)
                await store.load(silent: true)
                throw error
            }
        }
    }

}

private struct ReviewRow: View {
    let entry: ReviewEntry
    let onAdd: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(3)

            if !entry.authors.isEmpty || !entry.journal.isEmpty {
                Text(metaLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !entry.reasoning.isEmpty {
                Text(entry.reasoning)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if !entry.confidence.isEmpty {
                    Text(entry.confidence)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    onSkip()
                } label: {
                    Text("Skip")
                }
                .buttonStyle(.glass)

                Button {
                    onAdd()
                } label: {
                    Text("Add")
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(.vertical, 4)
    }

    private var metaLine: String {
        let parts = [entry.authors, entry.journal].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
