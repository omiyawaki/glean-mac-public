import SwiftUI

struct AuthorProposalsView: View {
    let store: AuthorStore
    let actionQueue: ActionQueueStore
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void

    var body: some View {
        Group {
            if !store.hasLoadedOnce {
                if let message = store.lastError {
                    ContentUnavailableView {
                        Label("Couldn't load proposals", systemImage: "exclamationmark.triangle")
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
                    "No author proposals",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("No first-authors have crossed the follow threshold lately.")
                )
            } else {
                List(store.entries) { proposal in
                    AuthorRow(
                        proposal: proposal,
                        onFollow: { perform(.follow, proposal: proposal) },
                        onDismiss: { perform(.dismiss, proposal: proposal) }
                    )
                }
            }
        }
        .task {
            if !store.hasLoadedOnce { await store.load() }
        }
    }

    private enum Kind {
        case follow, dismiss

        var title: String {
            switch self {
            case .follow: "Follow author"
            case .dismiss: "Dismiss author"
            }
        }

        var systemImage: String {
            switch self {
            case .follow: "person.crop.circle.badge.plus"
            case .dismiss: "archivebox"
            }
        }
    }

    /// Perform a Follow or Dismiss. Uses the same optimistic + explicit
    /// post-mutation load pattern as MaybeReviewView (the root fix).
    @MainActor
    private func perform(_ kind: Kind, proposal: AuthorProposal) {
        let id = proposal.id
        store.optimisticallyRemove(id: id)
        actionQueue.enqueue(
            title: kind.title,
            detail: proposal.author,
            systemImage: kind.systemImage
        ) {
            store.optimisticallyRemove(id: id)
            do {
                switch kind {
                case .follow:
                    try await offlineCoordinator.queueAuthorFollow(author: proposal.author)
                case .dismiss:
                    try await offlineCoordinator.queueAuthorDismiss(author: proposal.author)
                }
                await syncPendingOperations()

                // Root fix for the reappearance flash: after the server has
                // committed the removal, immediately load the authoritative
                // state. The apply() auto-pruning will clean up the optimistic
                // guard. For "follow" this is especially important because the
                // mutation does not emit an intake-changed event.
                await store.loadAfterLocalMutation(silent: true)

                store.releaseOptimisticRemoval(id: id)
            } catch {
                store.releaseOptimisticRemoval(id: id)
                await store.load(silent: true)
                throw error
            }
        }
    }

}

private struct AuthorRow: View {
    let proposal: AuthorProposal
    let onFollow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.author)
                    .font(.headline)
                Spacer()
                Text(proposal.count == 1 ? "1 paper saved" : "\(proposal.count) papers saved")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if !proposal.samples.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(proposal.samples, id: \.doi) { sample in
                        Text(sample.title)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Text("Dismiss")
                }
                .buttonStyle(.glass)

                Button {
                    onFollow()
                } label: {
                    Text("Follow")
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(.vertical, 4)
    }
}
