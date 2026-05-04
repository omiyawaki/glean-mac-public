import SwiftUI

struct ActionQueueButton: View {
    @Bindable var queue: ActionQueueStore

    var body: some View {
        Button {
            queue.isPresented.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Label("Activity", systemImage: systemImage)
                    .labelStyle(.iconOnly)
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(badgeColor, in: Capsule())
                        .offset(x: 7, y: -7)
                }
            }
        }
        .help("Activity")
        .popover(isPresented: $queue.isPresented, arrowEdge: .bottom) {
            ActionQueuePopover(queue: queue)
                .frame(width: 380, height: 420)
        }
    }

    private var badgeCount: Int {
        queue.failedCount > 0 ? queue.failedCount : queue.activeCount
    }

    private var badgeColor: Color {
        queue.failedCount > 0 ? .red : .accentColor
    }

    private var systemImage: String {
        if queue.failedCount > 0 { return "exclamationmark.triangle" }
        if queue.activeCount > 0 { return "clock.arrow.circlepath" }
        if queue.entries.isEmpty { return "tray" }
        return "checkmark.circle"
    }
}

private struct ActionQueuePopover: View {
    @Bindable var queue: ActionQueueStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Button {
                    queue.clearFinished()
                } label: {
                    Label("Clear Finished", systemImage: "checkmark.circle")
                }
                .labelStyle(.iconOnly)
                .help("Clear finished")
                .disabled(!queue.hasFinishedEntries)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if queue.entries.isEmpty {
                ContentUnavailableView(
                    "No recent activity",
                    systemImage: "checkmark.circle"
                )
            } else {
                List(queue.entries) { entry in
                    ActionQueueRow(entry: entry,
                                   retry: { queue.retry(entry.id) },
                                   remove: { queue.remove(entry.id) })
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct ActionQueueRow: View {
    let entry: ActionQueueStore.Entry
    let retry: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline)
                    .lineLimit(2)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if entry.status == .failed {
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Retry")
                .buttonStyle(.borderless)
            }

            if entry.status.isFinished {
                Button(action: remove) {
                    Label("Remove", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .help("Remove")
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch entry.status {
        case .queued, .running:
            ProgressView()
                .controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusText: String {
        switch entry.status {
        case .queued:
            return "Queued"
        case .running:
            return "Working"
        case .succeeded:
            return "Done"
        case .failed:
            return entry.errorMessage ?? "Failed"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .failed: .red
        case .succeeded: .secondary
        case .queued, .running: .secondary
        }
    }
}
