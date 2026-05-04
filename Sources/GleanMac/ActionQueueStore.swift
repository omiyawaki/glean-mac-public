import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ActionQueueStore {
    enum Status: String {
        case queued
        case running
        case succeeded
        case failed

        var isFinished: Bool {
            switch self {
            case .succeeded, .failed: true
            case .queued, .running: false
            }
        }
    }

    struct Entry: Identifiable {
        let id: UUID
        let title: String
        let detail: String
        let systemImage: String
        let createdAt: Date
        var status: Status
        var errorMessage: String?
        var completedAt: Date?
    }

    var entries: [Entry] = []
    var isPresented = false

    @ObservationIgnored
    private var operations: [UUID: @MainActor @Sendable () async throws -> Void] = [:]

    var activeCount: Int {
        entries.filter { !$0.status.isFinished }.count
    }

    var failedCount: Int {
        entries.filter { $0.status == .failed }.count
    }

    var hasFinishedEntries: Bool {
        entries.contains { $0.status.isFinished }
    }

    @discardableResult
    func enqueue(title: String,
                 detail: String = "",
                 systemImage: String,
                 operation: @escaping @MainActor @Sendable () async throws -> Void) -> UUID {
        let id = UUID()
        operations[id] = operation
        let entry = Entry(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            createdAt: Date(),
            status: .queued
        )
        withAnimation(.smooth) {
            entries.insert(entry, at: 0)
        }
        start(id)
        return id
    }

    func retry(_ id: UUID) {
        guard operations[id] != nil,
              let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].status == .failed else { return }
        entries[index].status = .queued
        entries[index].errorMessage = nil
        entries[index].completedAt = nil
        start(id)
    }

    func remove(_ id: UUID) {
        operations[id] = nil
        withAnimation(.smooth) {
            entries.removeAll { $0.id == id }
        }
    }

    func clearFinished() {
        let finished = Set(entries.filter { $0.status.isFinished }.map(\.id))
        for id in finished {
            operations[id] = nil
        }
        withAnimation(.smooth) {
            entries.removeAll { finished.contains($0.id) }
        }
    }

    private func start(_ id: UUID) {
        guard let operation = operations[id] else { return }
        Task { [weak self] in
            await self?.run(id: id, operation: operation)
        }
    }

    private func run(id: UUID,
                     operation: @escaping @MainActor @Sendable () async throws -> Void) async {
        update(id) { entry in
            entry.status = .running
            entry.errorMessage = nil
        }

        do {
            try await operation()
            operations[id] = nil
            update(id) { entry in
                entry.status = .succeeded
                entry.completedAt = Date()
            }
        } catch {
            update(id) { entry in
                entry.status = .failed
                entry.errorMessage = error.localizedDescription
                entry.completedAt = Date()
            }
        }
    }

    private func update(_ id: UUID, mutate: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
    }
}
