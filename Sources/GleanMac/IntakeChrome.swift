import SwiftUI

/// Helpers shared by the four list views — refresh-button toolbar
/// item with the in-button spinner during loads, and a relative-time
/// formatter for the "Updated X ago" subtitle suffix.

struct RefreshButton: View {
    let isLoading: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .disabled(isLoading)
        .help("Refresh")
    }
}

/// "Updated just now" for the first minute, otherwise "Updated 5 min ago"
/// using RelativeDateTimeFormatter (.short). Apple HIG-style freshness
/// affordance, mirrors Mail / Notes / Reminders.
func relativeUpdated(from when: Date, to now: Date) -> String {
    let delta = now.timeIntervalSince(when)
    if delta < 60 { return "Updated just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return "Updated " + formatter.localizedString(for: when, relativeTo: now)
}
