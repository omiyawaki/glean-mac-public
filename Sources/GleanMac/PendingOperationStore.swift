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

    init(url: URL) {
        self.url = url
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
    }

    @discardableResult
    func enqueue(_ kind: PendingOperation.Kind,
                 id: UUID = UUID(),
                 createdAt: Date = Date()) async throws -> PendingOperation {
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
        try await update(id: id) { operation in
            operation.status = .synced
            operation.errorMessage = nil
            operation.updatedAt = Date()
        }
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
        operations.removeAll { $0.id == id }
        try await save()
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
}
