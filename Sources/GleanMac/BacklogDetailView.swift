import SwiftUI
import AppKit

struct BacklogDetailView: View {
    let entry: BacklogEntry?
    @Binding var inspectorPresented: Bool

    var body: some View {
        Group {
            if let entry, let url = doiURL(for: entry) {
                WebViewer(url: url)
                    .navigationTitle(entry.title)
                    .navigationSubtitle(entry.doi)
            } else if entry != nil {
                ContentUnavailableView(
                    "No DOI to open",
                    systemImage: "link",
                    description: Text("This backlog entry has no resolvable DOI.")
                )
            } else {
                ContentUnavailableView(
                    "No paper selected",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Choose a paper from the backlog to find its PDF online, then drop the file onto the row to attach it.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let entry, let url = doiURL(for: entry) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
                .keyboardShortcut("l", modifiers: .command)
                .help("Open this DOI in Safari")
                .disabled(entry == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: .command)
                .help("Show metadata inspector")
                .disabled(entry == nil)
            }
        }
    }

    private func doiURL(for entry: BacklogEntry) -> URL? {
        guard !entry.doi.isEmpty else { return nil }
        return URL(string: "https://doi.org/\(entry.doi)")
    }
}
