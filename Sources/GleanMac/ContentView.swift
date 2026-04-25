import SwiftUI

enum SidebarItem: String, Hashable, Identifiable, CaseIterable {
    case libraryAll
    case backlog
    case maybeReview
    case authorProposals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .libraryAll: "All Papers"
        case .backlog: "Backlog"
        case .maybeReview: "Maybe Review"
        case .authorProposals: "Author Proposals"
        }
    }

    var systemImage: String {
        switch self {
        case .libraryAll: "books.vertical"
        case .backlog: "tray.and.arrow.down"
        case .maybeReview: "questionmark.circle"
        case .authorProposals: "person.crop.circle.badge.plus"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .backlog
    @State private var backlogStore = BacklogStore()
    @State private var reviewStore = ReviewStore()
    @State private var authorStore = AuthorStore()
    @State private var uploadStore = UploadStore()
    @State private var eventStream: EventStream?

    private static let eventsURL = URL(
        string: "http://backend.example.com:8765/events"
    )!

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    Label(SidebarItem.libraryAll.label,
                          systemImage: SidebarItem.libraryAll.systemImage)
                        .tag(SidebarItem.libraryAll)
                }
                Section("Intake") {
                    Label(SidebarItem.backlog.label,
                          systemImage: SidebarItem.backlog.systemImage)
                        .tag(SidebarItem.backlog)
                    Label(SidebarItem.maybeReview.label,
                          systemImage: SidebarItem.maybeReview.systemImage)
                        .tag(SidebarItem.maybeReview)
                    Label(SidebarItem.authorProposals.label,
                          systemImage: SidebarItem.authorProposals.systemImage)
                        .tag(SidebarItem.authorProposals)
                }
            }
            .navigationTitle("glean")
        } detail: {
            switch selection {
            case .backlog:
                BacklogView(store: backlogStore, uploads: uploadStore)
            case .maybeReview:
                MaybeReviewView(store: reviewStore)
            case .authorProposals:
                AuthorProposalsView(store: authorStore)
            case .libraryAll:
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
            let backlog = backlogStore
            let review = reviewStore
            let author = authorStore
            let stream = EventStream(url: Self.eventsURL) {
                async let a: Void = backlog.load(silent: true)
                async let b: Void = review.load(silent: true)
                async let c: Void = author.load(silent: true)
                _ = await (a, b, c)
            }
            stream.start()
            eventStream = stream
        }
    }
}
