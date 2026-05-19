import SwiftUI

struct AuthorProposalsView: View {
    let store: AuthorStore
    let actionQueue: ActionQueueStore
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void
    @State private var now = Date()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
        .navigationTitle("Author Proposals")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RefreshButton(isLoading: store.isLoading) {
                    await store.load()
                }
            }
        }
        .task {
            if !store.hasLoadedOnce { await store.load() }
        }
        .onReceive(ticker) { now = $0 }
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
            switch kind {
            case .follow:
                try await offlineCoordinator.queueAuthorFollow(author: proposal.author)
            case .dismiss:
                try await offlineCoordinator.queueAuthorDismiss(author: proposal.author)
            }
            store.releaseOptimisticRemoval(id: id)
            await syncPendingOperations()
        }
    }

    private var subtitle: String {
        guard store.hasLoadedOnce else { return "" }
        let countPart = store.count == 1
            ? "1 author proposed"
            : "\(store.count) authors proposed"
        guard let when = store.lastRefreshedAt else { return countPart }
        return "\(countPart) • \(relativeUpdated(from: when, to: now))"
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
