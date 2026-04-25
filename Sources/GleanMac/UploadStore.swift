import Foundation
import Observation
import SwiftUI

/// Tracks in-flight PDF uploads so the UI can show a "Uploading…" Section
/// above the backlog list while the multipart POST is running. On
/// completion the entry is removed via .smooth animation; on failure the
/// caller surfaces the error in an alert and the entry is removed too —
/// no permanent failure state in the list.
@MainActor
@Observable
final class UploadStore {
    struct InFlight: Identifiable {
        let id = UUID()
        let filename: String
    }

    var entries: [InFlight] = []

    /// Upload a PDF and remove it from the in-flight list on completion
    /// (success or failure). Throws on failure so the caller can present
    /// an alert.
    func upload(_ url: URL) async throws {
        let entry = InFlight(filename: url.lastPathComponent)
        let id = entry.id
        withAnimation(.smooth) {
            entries.append(entry)
        }
        defer {
            withAnimation(.smooth) {
                entries.removeAll { $0.id == id }
            }
        }
        try await IntakeActions.attach(file: url)
    }
}
