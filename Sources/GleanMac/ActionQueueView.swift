import SwiftUI

struct ActionQueueButton: View {
    @Bindable var queue: ActionQueueStore
    var backlogStore: BacklogStore? = nil
    var pendingStore: PendingOperationStore? = nil
    var syncPendingOperations: (() async -> Void)? = nil

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
            ActionQueuePopover(
                queue: queue,
                backlogStore: backlogStore,
                pendingStore: pendingStore,
                syncPendingOperations: syncPendingOperations
            )
                .frame(width: 380, height: 420)
        }
    }

    private var badgeCount: Int {
        let attention = queue.failedCount + pendingAttentionCount
        if attention > 0 { return attention }
        return queue.activeCount + pendingActiveCount
    }

    private var badgeColor: Color {
        let attention = queue.failedCount + pendingAttentionCount
        return attention > 0 ? .red : .accentColor
    }

    private var systemImage: String {
        if queue.failedCount + pendingAttentionCount > 0 {
            return "exclamationmark.triangle"
        }
        if queue.activeCount + pendingActiveCount > 0 {
            return "clock.arrow.circlepath"
        }
        if queue.entries.isEmpty && pendingRows.isEmpty { return "tray" }
        return "checkmark.circle"
    }

    private var pendingRows: [PendingOperationPresentation.Row] {
        PendingOperationPresentation.rows(for: pendingStore?.operations ?? [])
    }

    private var pendingAttentionCount: Int {
        PendingOperationPresentation.attentionCount(for: pendingStore?.operations ?? [])
    }

    private var pendingActiveCount: Int {
        PendingOperationPresentation.activeCount(for: pendingStore?.operations ?? [])
    }
}

private struct ActionQueuePopover: View {
    @Bindable var queue: ActionQueueStore
    var backlogStore: BacklogStore?
    var pendingStore: PendingOperationStore?
    var syncPendingOperations: (() async -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                if syncPendingOperations != nil {
                    Button {
                        Task { await syncPendingOperations?() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .actionQueueIconStyle()
                    }
                    .buttonStyle(.borderless)
                    .help("Sync pending changes")
                    .disabled(pendingRows.isEmpty)
                }
                Button {
                    queue.clearFinished()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .actionQueueIconStyle()
                }
                .buttonStyle(.borderless)
                .help("Clear finished")
                .disabled(!queue.hasFinishedEntries)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if queue.entries.isEmpty && pendingRows.isEmpty {
                ContentUnavailableView(
                    "No recent activity",
                    systemImage: "checkmark.circle"
                )
            } else {
                List {
                    if !pendingRows.isEmpty {
                        Section("Pending Sync") {
                            ForEach(pendingRows) { row in
                                PendingOperationRow(
                                    row: row,
                                    backlogEntries: backlogStore?.entries ?? [],
                                    chooseTarget: { citekey in
                                        Task {
                                            try? await pendingStore?.assignAttachTarget(
                                                id: row.id,
                                                citekey: citekey
                                            )
                                            await syncPendingOperations?()
                                        }
                                    },
                                    dismiss: {
                                        Task {
                                            try? await pendingStore?.remove(id: row.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    if !queue.entries.isEmpty {
                        Section("Recent") {
                            ForEach(queue.entries) { entry in
                                ActionQueueRow(
                                    entry: entry,
                                    backlogEntries: backlogStore?.entries ?? [],
                                    canForceAttach: queue.canForceAttach(entry.id),
                                    retry: { queue.retry(entry.id) },
                                    remove: { queue.remove(entry.id) },
                                    forceAttach: { citekey in
                                        queue.forceAttach(entry.id, citekey: citekey)
                                    }
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var pendingRows: [PendingOperationPresentation.Row] {
        PendingOperationPresentation.rows(for: pendingStore?.operations ?? [])
    }
}

private struct ActionQueueRow: View {
    let entry: ActionQueueStore.Entry
    let backlogEntries: [BacklogEntry]
    let canForceAttach: Bool
    let retry: () -> Void
    let remove: () -> Void
    let forceAttach: (String) -> Void

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

            if entry.status == .failed && canForceAttach && !backlogEntries.isEmpty {
                Menu {
                    Section("Attach to backlog entry") {
                        ForEach(backlogEntries) { backlogEntry in
                            Button {
                                forceAttach(backlogEntry.citekey)
                            } label: {
                                Text(backlogEntry.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "link.badge.plus")
                        .actionQueueIconStyle()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Attach anyway to a backlog entry")
            }

            if entry.status == .failed {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .actionQueueIconStyle()
                }
                .buttonStyle(.borderless)
                .help("Retry")
            }

            if entry.status.isFinished {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .actionQueueIconStyle()
                }
                .buttonStyle(.borderless)
                .help("Remove")
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

private struct PendingOperationRow: View {
    let row: PendingOperationPresentation.Row
    let backlogEntries: [BacklogEntry]
    let chooseTarget: (String) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Label(row.title, systemImage: row.systemImage)
                    .font(.subheadline)
                    .lineLimit(2)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(row.statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if row.canChooseTarget && !backlogEntries.isEmpty {
                Menu {
                    Section("Attach to backlog entry") {
                        ForEach(backlogEntries) { entry in
                            Button {
                                chooseTarget(entry.citekey)
                            } label: {
                                Text(entry.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "link.badge.plus")
                        .actionQueueIconStyle()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose target paper")
            }

            if row.status == .failed || row.status == .needsReview {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .actionQueueIconStyle()
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch row.status {
        case .queued, .running:
            ProgressView()
                .controlSize(.small)
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .needsReview:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .failed:
            return .red
        case .needsReview:
            return .orange
        case .queued, .running, .synced:
            return .secondary
        }
    }
}

private extension View {
    /// Standardize the look of the iconOnly buttons in the Activity
    /// popover. Without this, `arrow.clockwise` reads heavier than
    /// `xmark` at the default body size (different stroke densities)
    /// and the two glyphs sit on slightly different baselines because
    /// Label(...).iconOnly still allocates space for the hidden title
    /// text. Using Image(systemName:) + a fixed frame at .imageScale
    /// .medium pins both the glyph metrics and the click target.
    func actionQueueIconStyle() -> some View {
        self
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
            .symbolRenderingMode(.monochrome)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
}
