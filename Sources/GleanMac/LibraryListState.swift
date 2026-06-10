import Foundation
import Observation

enum LibraryListIdentity {
    static func value(forQuery query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "library-all"
            : "library-filtered"
    }
}

@MainActor
@Observable
final class LibraryListState {
    struct Result: Equatable {
        let visibleCount: Int
        let grouped: [LibraryFilter.YearGroup]
    }

    enum Mode {
        case all
        case filtered
    }

    typealias Recompute = ([LibraryEntry], String) -> Result

    var allGrouped: [LibraryFilter.YearGroup] = []
    var filteredGrouped: [LibraryFilter.YearGroup] = []
    var visibleCount: Int = 0
    var mode: Mode = .all

    var grouped: [LibraryFilter.YearGroup] {
        switch mode {
        case .all:
            allGrouped
        case .filtered:
            filteredGrouped
        }
    }

    private var lastEntries: [LibraryEntry]?
    private var lastQuery: String?
    private var allVisibleCount: Int = 0
    private var filteredVisibleCount: Int = 0
    @ObservationIgnored private let recompute: Recompute

    init(recompute: @escaping Recompute = LibraryListState.defaultRecompute) {
        self.recompute = recompute
    }

    func update(entries: [LibraryEntry], query: String) {
        guard entries != lastEntries || query != lastQuery else { return }

        if entries != lastEntries {
            let result = recompute(entries, "")
            allGrouped = result.grouped
            allVisibleCount = result.visibleCount
        }

        if LibraryListIdentity.value(forQuery: query) == "library-all" {
            mode = .all
            visibleCount = allVisibleCount
        } else {
            let result = recompute(entries, query)
            filteredGrouped = result.grouped
            filteredVisibleCount = result.visibleCount
            mode = .filtered
            visibleCount = filteredVisibleCount
        }

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
