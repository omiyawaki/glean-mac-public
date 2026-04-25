import SwiftUI

struct BacklogView: View {
    @State private var store = BacklogStore()

    var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                ProgressView().controlSize(.large)
            case .loaded(let payload):
                List(payload.entries) { entry in
                    BacklogRow(entry: entry)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load backlog", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await store.load() } }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("Intake Backlog")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.load() }
                }
            }
        }
        .task { await store.load() }
    }

    private var subtitle: String {
        if case .loaded(let payload) = store.state {
            return "\(payload.count) papers awaiting PDFs"
        }
        return ""
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
