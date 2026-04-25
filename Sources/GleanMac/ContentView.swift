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
    @State private var backlogSelection: String?
    @State private var librarySelection: String?
    @State private var inspectorPresented = false

    @State private var backlogStore = Stores.backlog()
    @State private var reviewStore = Stores.review()
    @State private var authorStore = Stores.author()
    @State private var libraryStore = Stores.library()
    @State private var libraryDetailStore = LibraryDetailStore()
    @State private var uploadStore = UploadStore()
    @State private var eventStream: EventStream?

    private static let eventsURL = URL(
        string: "http://backend.example.com:8765/events"
    )!

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            content
        } detail: {
            detail
        }
        .inspector(isPresented: $inspectorPresented) {
            inspector
                .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
        }
        .task {
            guard eventStream == nil else { return }
            let backlog = backlogStore
            let review = reviewStore
            let author = authorStore
            let library = libraryStore
            let stream = EventStream(url: Self.eventsURL) { event in
                switch event {
                case "intake-changed":
                    async let a: Void = backlog.load(silent: true)
                    async let b: Void = review.load(silent: true)
                    async let c: Void = author.load(silent: true)
                    _ = await (a, b, c)
                case "library-changed":
                    await library.load(silent: true)
                default:
                    break
                }
            }
            stream.start()
            eventStream = stream
        }
    }

    @ViewBuilder
    private var sidebar: some View {
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
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .libraryAll:
            LibraryView(store: libraryStore, selection: $librarySelection)
        case .backlog:
            BacklogView(store: backlogStore,
                        uploads: uploadStore,
                        selection: $backlogSelection)
        case .maybeReview:
            MaybeReviewView(store: reviewStore)
        case .authorProposals:
            AuthorProposalsView(store: authorStore)
        case .none:
            ContentUnavailableView(
                "Select a section",
                systemImage: "sidebar.left"
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .libraryAll:
            LibraryDetailView(
                citekey: librarySelection,
                store: libraryDetailStore,
                inspectorPresented: $inspectorPresented
            )
        case .backlog:
            BacklogDetailView(
                entry: selectedBacklogEntry,
                inspectorPresented: $inspectorPresented
            )
        case .maybeReview, .authorProposals, .none:
            ContentUnavailableView(
                "No detail",
                systemImage: "sidebar.right",
                description: Text("Use the Add/Skip buttons in the list to act on each item.")
            )
        }
    }

    @ViewBuilder
    private var inspector: some View {
        switch selection {
        case .libraryAll:
            LibraryMetadataInspector(record: libraryDetailStore.record)
        case .backlog:
            BacklogMetadataInspector(entry: selectedBacklogEntry)
        case .maybeReview, .authorProposals, .none:
            ContentUnavailableView(
                "No metadata",
                systemImage: "info.circle"
            )
        }
    }

    private var selectedBacklogEntry: BacklogEntry? {
        guard let id = backlogSelection else { return nil }
        return backlogStore.entries.first(where: { $0.id == id })
    }
}
