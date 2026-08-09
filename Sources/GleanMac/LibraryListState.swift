import Foundation
import Observation

enum LibraryListIdentity {
    static func value(forQuery query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "library-all"
            : "library-filtered"
    }
}

enum LibraryListRow: Identifiable, Equatable {
    case header(id: String, title: String)
    case paper(LibraryEntry)

    var id: String {
        switch self {
        case .header(let id, _): "header:\(id)"
        case .paper(let entry): "paper:\(entry.citekey)"
        }
    }

    static func rows(for groups: [LibraryFilter.YearGroup]) -> [LibraryListRow] {
        var rows: [LibraryListRow] = []
        rows.reserveCapacity(groups.count + groups.reduce(0) { $0 + $1.entries.count })
        for group in groups {
            let title = group.year.map(String.init) ?? "Undated"
            rows.append(.header(id: title, title: title))
            rows.append(contentsOf: group.entries.map(LibraryListRow.paper))
        }
        return rows
    }
}

@MainActor
@Observable
final class LibraryListState {
    struct Result: Equatable {
        let visibleCount: Int
        let grouped: [LibraryFilter.YearGroup]
        let rows: [LibraryListRow]
        let chronology: [LibraryChronology.Marker]
        let destinationPositions: [String: Double]

        init(
            visibleCount: Int,
            grouped: [LibraryFilter.YearGroup],
            chronology: [LibraryChronology.Marker]? = nil,
            destinationPositions: [String: Double]? = nil
        ) {
            let layout = chronology == nil || destinationPositions == nil
                ? LibraryChronology.layout(for: grouped)
                : nil
            self.visibleCount = visibleCount
            self.grouped = grouped
            self.rows = LibraryListRow.rows(for: grouped)
            self.chronology = chronology ?? layout?.markers ?? []
            self.destinationPositions = destinationPositions
                ?? layout?.destinationPositions
                ?? [:]
        }
    }

    enum Mode {
        case all
        case filtered
    }

    typealias Recompute = ([LibraryEntry], String) -> Result

    var allGrouped: [LibraryFilter.YearGroup] = []
    var filteredGrouped: [LibraryFilter.YearGroup] = []
    var allRows: [LibraryListRow] = []
    var filteredRows: [LibraryListRow] = []
    var allChronology: [LibraryChronology.Marker] = []
    var filteredChronology: [LibraryChronology.Marker] = []
    var allDestinationPositions: [String: Double] = [:]
    var filteredDestinationPositions: [String: Double] = [:]
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
            allRows = result.rows
            allChronology = result.chronology
            allDestinationPositions = result.destinationPositions
            allVisibleCount = result.visibleCount
        }

        if LibraryListIdentity.value(forQuery: query) == "library-all" {
            mode = .all
            visibleCount = allVisibleCount
        } else {
            let result = recompute(entries, query)
            filteredGrouped = result.grouped
            filteredRows = result.rows
            filteredChronology = result.chronology
            filteredDestinationPositions = result.destinationPositions
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
