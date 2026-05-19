import Foundation

enum PendingOperationPresentation {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let title: String
        let detail: String
        let statusText: String
        let systemImage: String
        let status: PendingOperation.Status
        let errorMessage: String?
        let canChooseTarget: Bool
    }

    static func rows(for operations: [PendingOperation]) -> [Row] {
        operations
            .filter { $0.status != .synced }
            .sorted { $0.createdAt > $1.createdAt }
            .map(row)
    }

    static func row(for operation: PendingOperation) -> Row {
        let summary = summary(for: operation.kind)
        return Row(
            id: operation.id,
            title: summary.title,
            detail: summary.detail,
            statusText: statusText(for: operation),
            systemImage: summary.systemImage,
            status: operation.status,
            errorMessage: operation.errorMessage,
            canChooseTarget: canChooseTarget(for: operation.kind)
        )
    }

    static func attentionCount(for operations: [PendingOperation]) -> Int {
        operations.filter {
            $0.status == .failed || $0.status == .needsReview
        }.count
    }

    static func activeCount(for operations: [PendingOperation]) -> Int {
        operations.filter {
            $0.status == .queued || $0.status == .running
        }.count
    }

    private static func summary(
        for kind: PendingOperation.Kind
    ) -> (title: String, detail: String, systemImage: String) {
        switch kind {
        case .reviewAdd(let doi):
            return ("Add review candidate", doi, "checkmark.circle")
        case .reviewSkip(let doi):
            return ("Skip review candidate", doi, "xmark.circle")
        case .authorFollow(let author):
            return ("Follow author", author, "person.crop.circle.badge.plus")
        case .authorDismiss(let author):
            return ("Dismiss author", author, "person.crop.circle.badge.minus")
        case .attachPDF(let stagedFilePath, let citekey):
            let filename = URL(fileURLWithPath: stagedFilePath).lastPathComponent
            if let citekey, !citekey.isEmpty {
                return ("Attach PDF", citekey, "paperclip")
            }
            return ("Match PDF", filename, "doc.viewfinder")
        case .addPaper(let input, _):
            return ("Add paper", input, "doc.badge.plus")
        }
    }

    private static func statusText(for operation: PendingOperation) -> String {
        switch operation.status {
        case .queued:
            return "Waiting to sync"
        case .running:
            return "Syncing"
        case .synced:
            return "Synced"
        case .failed:
            return operation.errorMessage ?? "Sync failed"
        case .needsReview:
            return operation.errorMessage ?? "Needs review"
        }
    }

    private static func canChooseTarget(for kind: PendingOperation.Kind) -> Bool {
        guard case .attachPDF(_, let citekey) = kind else { return false }
        return citekey == nil
    }
}
