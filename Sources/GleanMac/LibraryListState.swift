import Foundation
import Observation

@MainActor
@Observable
final class LibraryListState {
    struct Result: Equatable {
        let visibleCount: Int
        let grouped: [LibraryFilter.YearGroup]
    }

    typealias Recompute = ([LibraryEntry], String) -> Result

    var grouped: [LibraryFilter.YearGroup] = []
    var visibleCount: Int = 0

    private var lastEntries: [LibraryEntry]?
    private var lastQuery: String?
    @ObservationIgnored private let recompute: Recompute

    init(recompute: @escaping Recompute = LibraryListState.defaultRecompute) {
        self.recompute = recompute
    }

    func update(entries: [LibraryEntry], query: String) {
        guard entries != lastEntries || query != lastQuery else { return }
        let result = recompute(entries, query)
        grouped = result.grouped
        visibleCount = result.visibleCount
        lastEntries = entries
        lastQuery = query
    }

    private nonisolated static func defaultRecompute(
        entries: [LibraryEntry],
        query: String
    ) -> Result {
        let filtered = LibraryFilter.filter(entries, query: query)
        return Result(
            visibleCount: filtered.count,
            grouped: LibraryFilter.groupByYear(filtered)
        )
    }
}
