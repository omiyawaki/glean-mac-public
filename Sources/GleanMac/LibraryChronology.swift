import Foundation

enum LibraryChronology {
    struct Marker: Equatable {
        let id: String
        let destinationID: String
        let label: String
        let majorLabel: String?
        let railPosition: Double
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
        let yearOnlyDensityYear: Int?
        let contentPosition: Double
    }

    private struct PublicationPlacement {
        let navigationMonthOrdinal: Int?
        let yearOnlyDensityYear: Int?
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
    private static let calendarShare = 0.30
    private static let undatedRailGap = 0.03

    /// Builds a complete monthly chronology in visible-list order, then lays
    /// it out with a calendar-and-library-density blend. Empty months remain
    /// reachable, but sparse history does not consume most of the available
    /// rail. Empty months route to the next older paper. Year-only metadata is
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
                let placement = publicationPlacement(for: entry, groupYear: group.year)
                let position = destinations.isEmpty
                    ? 0
                    : min(max(visualOffset / totalWeight, 0), 1)
                let destination = Destination(
                    citekey: entry.citekey,
                    monthOrdinal: placement.navigationMonthOrdinal,
                    yearOnlyDensityYear: placement.yearOnlyDensityYear,
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
            let densityCounts = densityCounts(
                for: dated,
                newestMonth: newestMonth,
                oldestMonth: oldestMonth
            )
            let railPositions = densityWeightedRailPositions(
                newestMonth: newestMonth,
                oldestMonth: oldestMonth,
                densityCounts: densityCounts
            )
            let datedRailScale = destinations.contains { $0.monthOrdinal == nil }
                ? 1 - undatedRailGap
                : 1
            markers.reserveCapacity(newestMonth - oldestMonth + 2)
            var cursor = 0
            for (index, ordinal) in stride(
                from: newestMonth,
                through: oldestMonth,
                by: -1
            ).enumerated() {
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
                    railPosition: railPositions[index] * datedRailScale,
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
                railPosition: 1,
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

    private static func publicationPlacement(
        for entry: LibraryEntry,
        groupYear: Int?
    ) -> PublicationPlacement {
        if let parts = exactMonth(from: entry.publishedAt) {
            return PublicationPlacement(
                navigationMonthOrdinal: parts.year * 12 + parts.month - 1,
                yearOnlyDensityYear: nil
            )
        }
        guard let year = groupYear ?? entry.year else {
            return PublicationPlacement(
                navigationMonthOrdinal: nil,
                yearOnlyDensityYear: nil
            )
        }
        return PublicationPlacement(
            navigationMonthOrdinal: year * 12,
            yearOnlyDensityYear: year
        )
    }

    /// Exact dates contribute to their month. Year-only records contribute
    /// one twelfth to each month of that year, avoiding an artificial January
    /// spike while exact-date backfill is still running.
    private static func densityCounts(
        for destinations: [Destination],
        newestMonth: Int,
        oldestMonth: Int
    ) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for destination in destinations {
            if let year = destination.yearOnlyDensityYear {
                for monthOffset in 0..<12 {
                    let ordinal = year * 12 + monthOffset
                    guard (oldestMonth...newestMonth).contains(ordinal) else { continue }
                    result[ordinal, default: 0] += 1.0 / 12.0
                }
            } else if let ordinal = destination.monthOrdinal {
                result[ordinal, default: 0] += 1
            }
        }
        return result
    }

    /// Blends a real calendar axis with the cumulative square-root paper
    /// density. Empty spans keep 30% of their linear duration while occupied
    /// months receive the remaining space without letting very large months
    /// dominate in direct proportion to their paper count.
    private static func densityWeightedRailPositions(
        newestMonth: Int,
        oldestMonth: Int,
        densityCounts: [Int: Double]
    ) -> [Double] {
        let monthCount = newestMonth - oldestMonth + 1
        guard monthCount > 1 else { return [0] }

        let masses = stride(from: newestMonth, through: oldestMonth, by: -1).map {
            sqrt(densityCounts[$0, default: 0])
        }
        let intervalMasses = zip(masses, masses.dropFirst()).map { lhs, rhs in
            (lhs + rhs) / 2
        }
        let totalDensityMass = intervalMasses.reduce(0, +)
        var cumulativeDensityMass = 0.0
        var positions: [Double] = []
        positions.reserveCapacity(monthCount)

        for index in 0..<monthCount {
            let calendarPosition = Double(index) / Double(monthCount - 1)
            let densityPosition = totalDensityMass > 0
                ? cumulativeDensityMass / totalDensityMass
                : calendarPosition
            positions.append(
                calendarShare * calendarPosition
                    + (1 - calendarShare) * densityPosition
            )
            if index < intervalMasses.count {
                cumulativeDensityMass += intervalMasses[index]
            }
        }

        positions[0] = 0
        positions[positions.count - 1] = 1
        return positions
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
