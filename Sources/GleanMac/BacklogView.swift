import SwiftUI

struct BacklogView: View {
    let store: BacklogStore
    @State private var now = Date()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !store.hasLoadedOnce {
                if let message = store.lastError {
                    ContentUnavailableView {
                        Label("Couldn't load backlog", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { Task { await store.load() } }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ProgressView().controlSize(.large)
                }
            } else {
                List(store.entries) { entry in
                    BacklogRow(entry: entry)
                }
            }
        }
        .navigationTitle("Intake")
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
            if !store.hasLoadedOnce {
                await store.load()
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    private var subtitle: String {
        guard store.hasLoadedOnce else { return "" }
        let countPart = store.count == 1
            ? "1 paper awaiting PDF"
            : "\(store.count) papers awaiting PDFs"
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

struct BacklogRow: View {
    let entry: BacklogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(entry.citekey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.doi)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
