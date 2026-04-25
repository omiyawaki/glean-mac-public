import SwiftUI

struct BacklogView: View {
    @State private var store = BacklogStore()

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
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.load() }
                }
                .disabled(store.isLoading)
            }
        }
        .task { await store.load() }
    }

    private var subtitle: String {
        guard store.hasLoadedOnce else { return "" }
        return store.count == 1
            ? "1 paper awaiting PDF"
            : "\(store.count) papers awaiting PDFs"
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
