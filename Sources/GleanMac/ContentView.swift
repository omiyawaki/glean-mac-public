import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case library
    case backlog

    var id: String { rawValue }

    var label: String {
        switch self {
        case .library: "Library"
        case .backlog: "Intake"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .backlog: "tray.and.arrow.down"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .backlog
    @State private var backlogStore = BacklogStore()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.label, systemImage: item.systemImage).tag(item)
            }
            .navigationTitle("glean")
        } detail: {
            switch selection {
            case .backlog:
                BacklogView(store: backlogStore)
            case .library:
                ContentUnavailableView(
                    "Library",
                    systemImage: "books.vertical",
                    description: Text("Coming soon.")
                )
            case .none:
                ContentUnavailableView(
                    "Select a section",
                    systemImage: "sidebar.left"
                )
            }
        }
    }
}
