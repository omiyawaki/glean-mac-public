import Foundation

enum LibraryChronology {
    struct Marker: Equatable {
        let id: String
        let destinationID: String
        let label: String
        let majorLabel: String?
        let contentPosition: Double
        let isYearBoundary: Bool
    }

    struct Layout: Equatable {
        let markers: [Marker]
        let destinationPositions: [String: Double]
    }

    private struct Destination {
        let citekey: String
        let monthOrdinal: Int?
        let contentPosition: Double
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// A section header occupies roughly half the visual height of a fixed
    /// library row. Keeping that weight in the destination map makes
    /// normalized, pixel-based jumps land close to the first paper in a
    /// month without asking SwiftUI to resolve thousands of semantic row IDs.
    private static let sectionHeaderWeight = 0.5

    /// Builds a true calendar scale in visible list order. The scale contains
    /// every month between the newest and oldest dated library entries, so
    /// equal distances always represent equal spans of publication time.
    /// Empty months route to the next older paper. Year-only metadata is
    /// placed at January for navigation only; no date is written to metadata.
    static func layout(for groups: [LibraryFilter.YearGroup]) -> Layout {
        let entryCount = groups.reduce(0) { $0 + $1.entries.count }
        guard entryCount > 0 else {
            return Layout(markers: [], destinationPositions: [:])
        }

        let totalWeight = Double(entryCount)
            + Double(groups.count) * sectionHeaderWeight
        var visualOffset = 0.0
        var destinations: [Destination] = []
        destinations.reserveCapacity(entryCount)
        var destinationPositions: [String: Double] = [:]
        destinationPositions.reserveCapacity(entryCount)

        for group in groups {
            visualOffset += sectionHeaderWeight
            for entry in group.entries {
                let position = destinations.isEmpty
                    ? 0
                    : min(max(visualOffset / totalWeight, 0), 1)
                let destination = Destination(
                    citekey: entry.citekey,
                    monthOrdinal: monthOrdinal(for: entry, groupYear: group.year),
                    contentPosition: position
                )
                destinations.append(destination)
                destinationPositions[entry.citekey] = position
                visualOffset += 1
            }
        }

        let dated = destinations.filter { $0.monthOrdinal != nil }
        var markers: [Marker] = []

        if let newestMonth = dated.first?.monthOrdinal,
           let oldestMonth = dated.last?.monthOrdinal {
            markers.reserveCapacity(newestMonth - oldestMonth + 2)
            var cursor = 0
            for ordinal in stride(from: newestMonth, through: oldestMonth, by: -1) {
                while cursor < dated.count - 1,
                      let cursorMonth = dated[cursor].monthOrdinal,
                      cursorMonth > ordinal {
                    cursor += 1
                }
                let destination = dated[cursor]
                let year = ordinal / 12
                let month = ordinal % 12 + 1
                let isEndpoint = ordinal == newestMonth || ordinal == oldestMonth
                let majorLabel = (month == 1 && year.isMultiple(of: 10)) || isEndpoint
                    ? String(year)
                    : nil
                markers.append(Marker(
                    id: String(format: "month:%04d-%02d", year, month),
                    destinationID: destination.citekey,
                    label: "\(monthNames[month - 1]) \(year)",
                    majorLabel: majorLabel,
                    contentPosition: destination.contentPosition,
                    isYearBoundary: month == 1
                ))
            }
        }

        if let undated = destinations.first(where: { $0.monthOrdinal == nil }) {
            markers.append(Marker(
                id: "undated",
                destinationID: undated.citekey,
                label: "Undated",
                majorLabel: "Undated",
                contentPosition: undated.contentPosition,
                isYearBoundary: false
            ))
        }

        return Layout(
            markers: markers,
            destinationPositions: destinationPositions
        )
    }

    static func markers(for groups: [LibraryFilter.YearGroup]) -> [Marker] {
        layout(for: groups).markers
    }

    private static func monthOrdinal(
        for entry: LibraryEntry,
        groupYear: Int?
    ) -> Int? {
        if let parts = exactMonth(from: entry.publishedAt) {
            return parts.year * 12 + parts.month - 1
        }
        guard let year = groupYear ?? entry.year else { return nil }
        return year * 12
    }

    private static func exactMonth(from value: String?) -> (year: Int, month: Int)? {
        guard let value else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month),
              Int(parts[2]) != nil else { return nil }
        return (year, month)
    }
}
