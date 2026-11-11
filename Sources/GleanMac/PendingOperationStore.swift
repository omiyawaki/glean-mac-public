import Foundation
import Observation

struct PendingOperation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        case reviewAdd(doi: String)
        case reviewSkip(doi: String)
        case authorFollow(author: String)
        case authorDismiss(author: String)
        case attachPDF(stagedFilePath: String, citekey: String?)
        case addPaper(input: String, stagedPDFPath: String?)
        case deletePaper(citekey: String, doi: String, title: String)
    }

    enum Status: String, Codable, Equatable, Sendable {
        case queued
        case running
        case synced
        case failed
        case needsReview
    }

    let id: UUID
    let createdAt: Date
    let kind: Kind
    var status: Status
    var errorMessage: String?
    var updatedAt: Date
}

@MainActor
@Observable
final class PendingOperationStore {
    var operations: [PendingOperation] = []

    private let url: URL
    private let managedPendingPDFDirectory: URL
    static let defaultStaleRunningInterval: TimeInterval = 20 * 60

    static var `default`: PendingOperationStore {
        PendingOperationStore(url: defaultURL)
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Glean", isDirectory: true)
            .appendingPathComponent("PendingOperations.json")
    }

    static var defaultPendingPDFDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Glean", isDirectory: true)
            .appendingPathComponent("PendingPDFs", isDirectory: true)
    }

    init(
        url: URL,
        managedPendingPDFDirectory: URL = PendingOperationStore.defaultPendingPDFDirectory
    ) {
        self.url = url
        self.managedPendingPDFDirectory = managedPendingPDFDirectory
    }

    var pendingOperations: [PendingOperation] {
        operations.filter { operation in
            switch operation.status {
            case .queued, .failed:
                true
            case .running, .synced, .needsReview:
                false
            }
        }
    }

    func load() async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            operations = []
            return
        }
        let data = try Data(contentsOf: url)
        operations = try JSONDecoder().decode([PendingOperation].self, from: data)
        if compactDuplicateAttachOperations() {
            try await save()
        }
    }

    @discardableResult
    func enqueue(_ kind: PendingOperation.Kind,
                 id: UUID = UUID(),
                 createdAt: Date = Date()) async throws -> PendingOperation {
        if let existing = try await coalesceAttachPDFIfNeeded(
            kind,
            updatedAt: createdAt
        ) {
            return existing
        }
        let operation = PendingOperation(
            id: id,
            createdAt: createdAt,
            kind: kind,
            status: .queued,
            errorMessage: nil,
            updatedAt: createdAt
        )
        operations.append(operation)
        try await save()
        return operation
    }

    func markRunning(id: UUID, now: Date = Date()) async throws {
        try await update(id: id) { operation in
            operation.status = .running
            operation.errorMessage = nil
            operation.updatedAt = now
        }
    }

    func markSynced(id: UUID) async throws {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        let operation = operations.remove(at: index)
        removeStagedFile(for: operation)
        try await save()
    }

    func markNeedsReview(id: UUID, message: String) async throws {
        try await update(id: id) { operation in
            operation.status = .needsReview
            operation.errorMessage = message
            operation.updatedAt = Date()
        }
    }

    func markFailed(id: UUID, message: String) async throws {
        try await update(id: id) { operation in
            operation.status = .failed
            operation.errorMessage = message
            operation.updatedAt = Date()
        }
    }

    func requeueStaleRunningOperations(
        now: Date = Date(),
        olderThan interval: TimeInterval = defaultStaleRunningInterval
    ) async throws {
        var didChange = false
        for index in operations.indices where operations[index].status == .running {
            guard now.timeIntervalSince(operations[index].updatedAt) >= interval else {
                continue
            }
            operations[index].status = .queued
            operations[index].errorMessage = nil
            operations[index].updatedAt = now
            didChange = true
        }
        if didChange {
            try await save()
        }
    }

    func remove(id: UUID) async throws {
        if let operation = operations.first(where: { $0.id == id }) {
            removeStagedFile(for: operation)
        }
        operations.removeAll { $0.id == id }
        try await save()
    }

    func stagedFileMissing(for operation: PendingOperation) -> Bool {
        guard let path = operation.stagedFilePath else { return false }
        return !FileManager.default.fileExists(atPath: path)
    }

    func assignAttachTarget(id: UUID, citekey: String) async throws {
        try await update(id: id) { operation in
            guard case .attachPDF(let stagedFilePath, _) = operation.kind else {
                return
            }
            operation = PendingOperation(
                id: operation.id,
                createdAt: operation.createdAt,
                kind: .attachPDF(stagedFilePath: stagedFilePath,
                                 citekey: citekey),
                status: .queued,
                errorMessage: nil,
                updatedAt: Date()
            )
        }
    }

    private func update(id: UUID, mutate: (inout PendingOperation) -> Void) async throws {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&operations[index])
        try await save()
    }

    private func coalesceAttachPDFIfNeeded(
        _ kind: PendingOperation.Kind,
        updatedAt: Date
    ) async throws -> PendingOperation? {
        guard case .attachPDF(let newPath, let citekey) = kind,
              let citekey,
              !citekey.isEmpty,
              let index = operations.firstIndex(where: {
                  $0.deduplicatesAttachPDF(for: citekey)
              })
        else {
            return nil
        }

        switch operations[index].status {
        case .queued, .running:
            removeManagedStagedFile(atPath: newPath)
        case .failed, .needsReview:
            let oldPath = operations[index].stagedFilePath
            operations[index] = PendingOperation(
                id: operations[index].id,
                createdAt: operations[index].createdAt,
                kind: .attachPDF(stagedFilePath: newPath, citekey: citekey),
                status: .queued,
                errorMessage: nil,
                updatedAt: updatedAt
            )
            if oldPath != newPath {
                removeManagedStagedFile(atPath: oldPath)
            }
            try await save()
        case .synced:
            break
        }
        return operations[index]
    }

    @discardableResult
    private func compactDuplicateAttachOperations() -> Bool {
        var changed = false
        var retainedByCitekey: [String: Int] = [:]
        var retainedOriginalIndices = Set<Int>()

        for index in operations.indices.sorted(by: {
            operations[$0].createdAt > operations[$1].createdAt
        }) {
            let operation = operations[index]
            if operation.status == .synced {
                removeStagedFile(for: operation)
                changed = true
                continue
            }
            guard let citekey = operation.attachPDFCitekey else {
                retainedOriginalIndices.insert(index)
                continue
            }
            if retainedByCitekey[citekey] == nil {
                retainedByCitekey[citekey] = index
                retainedOriginalIndices.insert(index)
            } else {
                removeStagedFile(for: operation)
                changed = true
            }
        }

        guard changed else { return false }
        operations = operations.indices
            .filter { retainedOriginalIndices.contains($0) }
            .map { operations[$0] }
        return true
    }

    private func save() async throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(operations)
        try data.write(to: url, options: [.atomic])
    }

    private func removeStagedFile(for operation: PendingOperation) {
        removeManagedStagedFile(atPath: operation.stagedFilePath)
    }

    private func removeManagedStagedFile(atPath path: String?) {
        guard let path else { return }
        let fileURL = URL(fileURLWithPath: path)
        guard isManagedPendingPDF(fileURL) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func isManagedPendingPDF(_ fileURL: URL) -> Bool {
        let directoryPath = managedPendingPDFDirectory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath.hasPrefix(directoryPath + "/")
    }
}

private extension PendingOperation {
    var attachPDFCitekey: String? {
        guard case .attachPDF(_, let citekey) = kind,
              let citekey,
              !citekey.isEmpty
        else {
            return nil
        }
        return citekey
    }

    var stagedFilePath: String? {
        switch kind {
        case .attachPDF(let stagedFilePath, _):
            return stagedFilePath
        case .addPaper(_, let stagedPDFPath):
            return stagedPDFPath
        case .reviewAdd, .reviewSkip, .authorFollow, .authorDismiss, .deletePaper:
            return nil
        }
    }

    func deduplicatesAttachPDF(for citekey: String) -> Bool {
        guard attachPDFCitekey == citekey else { return false }
        switch status {
        case .queued, .running, .failed, .needsReview:
            return true
        case .synced:
            return false
        }
    }
}
