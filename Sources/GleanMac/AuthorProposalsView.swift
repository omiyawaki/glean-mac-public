import SwiftUI

struct AuthorProposalsView: View {
    let store: AuthorStore
    @State private var now = Date()
    @State private var inFlight: Set<String> = []
    @State private var actionError: String?
    @State private var showError = false

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
                        isBusy: inFlight.contains(proposal.author),
                        onFollow: { await perform(.follow, proposal: proposal) },
                        onDismiss: { await perform(.dismiss, proposal: proposal) }
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
        .alert("Action failed",
               isPresented: $showError,
               presenting: actionError) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    private enum Kind { case follow, dismiss }

    private func perform(_ kind: Kind, proposal: AuthorProposal) async {
        inFlight.insert(proposal.author)
        defer { inFlight.remove(proposal.author) }
        do {
            switch kind {
            case .follow: try await IntakeActions.authorFollow(author: proposal.author)
            case .dismiss: try await IntakeActions.authorDismiss(author: proposal.author)
            }
        } catch {
            actionError = error.localizedDescription
            showError = true
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
    let isBusy: Bool
    let onFollow: () async -> Void
    let onDismiss: () async -> Void

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
                    Task { await onDismiss() }
                } label: {
                    Text("Dismiss")
                }
                .buttonStyle(.glass)
                .disabled(isBusy)

                Button {
                    Task { await onFollow() }
                } label: {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Follow")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 4)
    }
}
