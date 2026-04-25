import SwiftUI

struct BacklogView: View {
    let store: BacklogStore
    let uploads: UploadStore
    @State private var now = Date()
    @State private var actionError: String?
    @State private var showError = false

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
                List {
                    if !uploads.entries.isEmpty {
                        Section("Uploading") {
                            ForEach(uploads.entries) { upload in
                                UploadingRow(filename: upload.filename)
                            }
                        }
                    }
                    Section {
                        ForEach(store.entries) { entry in
                            BacklogRow(entry: entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("Backlog")
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
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            for url in pdfs {
                Task {
                    do {
                        try await uploads.upload(url)
                    } catch {
                        actionError = error.localizedDescription
                        showError = true
                    }
                }
            }
            return !pdfs.isEmpty
        }
        .alert("Upload failed",
               isPresented: $showError,
               presenting: actionError) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
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

private struct BacklogRow: View {
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

private struct UploadingRow: View {
    let filename: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(filename)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
