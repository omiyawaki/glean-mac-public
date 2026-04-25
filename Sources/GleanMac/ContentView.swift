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
    @State private var eventStream: EventStream?

    private static let eventsURL = URL(
        string: "http://backend.example.com:8765/events"
    )!

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
        .task {
            guard eventStream == nil else { return }
            let store = backlogStore
            let stream = EventStream(url: Self.eventsURL) {
                await store.load(silent: true)
            }
            stream.start()
            eventStream = stream
        }
    }
}
