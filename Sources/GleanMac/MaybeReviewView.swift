import SwiftUI

struct MaybeReviewView: View {
    let store: ReviewStore
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
                        isBusy: inFlight.contains(entry.doi),
                        onAdd: { await perform(.add, entry: entry) },
                        onSkip: { await perform(.skip, entry: entry) }
                    )
                }
            }
        }
        .navigationTitle("Maybe Review")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.load() }
                } label: {
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isLoading)
                .help("Refresh")
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

    private enum Kind { case add, skip }

    private func perform(_ kind: Kind, entry: ReviewEntry) async {
        inFlight.insert(entry.doi)
        defer { inFlight.remove(entry.doi) }
        do {
            switch kind {
            case .add: try await IntakeActions.reviewAdd(doi: entry.doi)
            case .skip: try await IntakeActions.reviewSkip(doi: entry.doi)
            }
            // On success: do nothing locally — the SSE event will fire when
            // the server rewrites review_queue.md, and the store will
            // silently refetch with the row removed.
        } catch {
            actionError = error.localizedDescription
            showError = true
        }
    }

    private var subtitle: String {
        guard store.hasLoadedOnce else { return "" }
        let countPart = store.count == 1
            ? "1 paper to review"
            : "\(store.count) papers to review"
        guard let when = store.lastRefreshedAt else { return countPart }
        return "\(countPart) • \(relativeUpdated(from: when))"
    }

    private func relativeUpdated(from when: Date) -> String {
        let delta = now.timeIntervalSince(when)
        if delta < 60 { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated " + formatter.localizedString(for: when, relativeTo: now)
    }
}

private struct ReviewRow: View {
    let entry: ReviewEntry
    let isBusy: Bool
    let onAdd: () async -> Void
    let onSkip: () async -> Void

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
                    Task { await onSkip() }
                } label: {
                    Text("Skip")
                }
                .buttonStyle(.glass)
                .disabled(isBusy)

                Button {
                    Task { await onAdd() }
                } label: {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 4)
    }

    private var metaLine: String {
        let parts = [entry.authors, entry.journal].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
