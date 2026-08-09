import Foundation

enum LibraryChronology {
    struct Marker: Equatable {
        let id: String
        let label: String
        let majorLabel: String?
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// Produces semantic scroll destinations in visible list order. Exact
    /// dates contribute one destination per represented month. A year-only
    /// destination remains available while that year's dates are absent.
    static func markers(for groups: [LibraryFilter.YearGroup]) -> [Marker] {
        var result: [Marker] = []
        result.reserveCapacity(groups.count * 3)

        for group in groups {
            var seenMonths: Set<String> = []
            var yearMarkers: [Marker] = []
            var firstPendingEntry: LibraryEntry?

            for entry in group.entries {
                guard let parts = exactMonth(from: entry.publishedAt) else {
                    if firstPendingEntry == nil {
                        firstPendingEntry = entry
                    }
                    continue
                }
                let key = String(format: "%04d-%02d", parts.year, parts.month)
                guard seenMonths.insert(key).inserted else { continue }
                yearMarkers.append(Marker(
                    id: entry.citekey,
                    label: "\(monthNames[parts.month - 1]) \(parts.year)",
                    majorLabel: yearMarkers.isEmpty ? String(parts.year) : nil
                ))
            }

            if yearMarkers.isEmpty, let entry = group.entries.first {
                let label = group.year.map(String.init) ?? "Undated"
                yearMarkers.append(Marker(
                    id: entry.citekey,
                    label: label,
                    majorLabel: label
                ))
            } else if let firstPendingEntry, let year = group.year {
                yearMarkers.append(Marker(
                    id: firstPendingEntry.citekey,
                    label: "\(year) (date pending)",
                    majorLabel: nil
                ))
            }
            result.append(contentsOf: yearMarkers)
        }
        return result
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
