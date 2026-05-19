import Foundation

enum SidebarContentChrome {
    static func title(for selection: SidebarItem?) -> String {
        switch selection {
        case .libraryAll: "All Papers"
        case .backlog: "Backlog"
        case .maybeReview: "Maybe Review"
        case .authorProposals: "Author Proposals"
        case .none: "Select a section"
        }
    }

    static func isRefreshAvailable(for selection: SidebarItem?) -> Bool {
        selection != nil
    }

    static func librarySubtitle(
        hasLoadedOnce: Bool,
        totalCount: Int,
        visibleCount: Int,
        lastRefreshedAt: Date?,
        now: Date
    ) -> String {
        guard hasLoadedOnce else { return "" }
        let countPart: String
        if visibleCount == totalCount {
            countPart = totalCount == 1 ? "1 paper" : "\(totalCount) papers"
        } else {
            countPart = "\(visibleCount) of \(totalCount) papers"
        }
        return subtitle(countPart: countPart, lastRefreshedAt: lastRefreshedAt, now: now)
    }

    static func backlogSubtitle(
        hasLoadedOnce: Bool,
        count: Int,
        lastRefreshedAt: Date?,
        now: Date
    ) -> String {
        guard hasLoadedOnce else { return "" }
        let countPart = count == 1
            ? "1 paper awaiting PDF"
            : "\(count) papers awaiting PDFs"
        return subtitle(countPart: countPart, lastRefreshedAt: lastRefreshedAt, now: now)
    }

    static func maybeReviewSubtitle(
        hasLoadedOnce: Bool,
        count: Int,
        lastRefreshedAt: Date?,
        now: Date
    ) -> String {
        guard hasLoadedOnce else { return "" }
        let countPart = count == 1
            ? "1 paper to review"
            : "\(count) papers to review"
        return subtitle(countPart: countPart, lastRefreshedAt: lastRefreshedAt, now: now)
    }

    static func authorProposalsSubtitle(
        hasLoadedOnce: Bool,
        count: Int,
        lastRefreshedAt: Date?,
        now: Date
    ) -> String {
        guard hasLoadedOnce else { return "" }
        let countPart = count == 1
            ? "1 author proposed"
            : "\(count) authors proposed"
        return subtitle(countPart: countPart, lastRefreshedAt: lastRefreshedAt, now: now)
    }

    private static func subtitle(
        countPart: String,
        lastRefreshedAt: Date?,
        now: Date
    ) -> String {
        guard let lastRefreshedAt else { return countPart }
        return "\(countPart) • \(relativeUpdated(from: lastRefreshedAt, to: now))"
    }
}
