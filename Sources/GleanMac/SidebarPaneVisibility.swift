import SwiftUI

struct MountedSidebarItems {
    private var items: Set<SidebarItem>

    init(initial: SidebarItem) {
        items = [initial]
    }

    mutating func select(_ item: SidebarItem?) {
        guard let item else { return }
        items.insert(item)
    }

    func contains(_ item: SidebarItem) -> Bool {
        items.contains(item)
    }
}

enum SidebarPaneVisibility {
    static let selectionAnimation: Animation? = nil

    static func opacity(for item: SidebarItem, selection: SidebarItem?) -> Double {
        item == selection ? 1 : 0
    }

    static func allowsHitTesting(for item: SidebarItem, selection: SidebarItem?) -> Bool {
        item == selection
    }
}

enum SidebarLaunchSelection {
    enum LoadState: Equatable {
        case notLoaded
        case loaded(count: Int)
    }

    static func preferredItem(
        backlog: LoadState,
        review: LoadState,
        authors: LoadState
    ) -> SidebarItem {
        if shouldShow(backlog) { return .backlog }
        if shouldShow(review) { return .maybeReview }
        if shouldShow(authors) { return .authorProposals }
        return .libraryAll
    }

    private static func shouldShow(_ state: LoadState) -> Bool {
        switch state {
        case .notLoaded:
            return true
        case .loaded(let count):
            return count > 0
        }
    }
}
