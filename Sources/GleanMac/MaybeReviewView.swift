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
            switch kind {
            case .add:
                try await offlineCoordinator.queueReviewAdd(doi: entry.doi)
            case .skip:
                try await offlineCoordinator.queueReviewSkip(doi: entry.doi)
            }
            store.releaseOptimisticRemoval(id: id)
            await syncPendingOperations()
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
