import AppleAppDesignSystem
import LocalAppUpdateKit
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
    @StateObject private var updateController = LocalAppUpdateController()
    @State private var selection: SidebarItem? = .backlog
    @State private var backlogSelection: String?
    @State private var librarySelection: String?
    @State private var libraryQuery = ""
    @State private var inspectorPresented = false

    @State private var backlogStore = Stores.backlog()
    @State private var reviewStore = Stores.review()
    @State private var authorStore = Stores.author()
    @State private var libraryStore = Stores.library()
    @State private var libraryListState = LibraryListState()
    @State private var libraryDetailStore = LibraryDetailStore()
    @State private var actionQueue = ActionQueueStore()
    @State private var operationStore = PendingOperationStore.default
    @State private var syncWorker: PendingOperationSyncWorker?
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
        .toolbar {
            // Use the ToolbarContent wrapper (matches the Laps app and the
            // pattern documented by AppleAppDesignSystem). It applies
            // .sharedBackgroundVisibility(.hidden) at the ToolbarItem level
            // so the glass button renders without the default toolbar-item
            // background frame -- using the bare LocalAppUpdateToolbarButton
            // inside a ToolbarItemGroup skips that and the button looks
            // boxed-in next to the other toolbar items.
            LocalAppUpdateToolbarItem(controller: updateController)
            ToolbarItem(placement: .primaryAction) {
                ActionQueueButton(
                    queue: actionQueue,
                    backlogStore: backlogStore,
                    pendingStore: operationStore,
                    syncPendingOperations: syncPendingOperations
                )
            }
        }
        .task {
            await updateController.checkForUpdates()
            guard eventStream == nil else { return }
            try? await operationStore.load()
            let pendingOperations = operationStore
            let sync = PendingOperationSyncWorker(store: pendingOperations)
            syncWorker = sync
            await sync.syncPending()
            let backlog = backlogStore
            let review = reviewStore
            let author = authorStore
            let library = libraryStore
            let stream = EventStream(url: Self.eventsURL) { event in
                switch event {
                case "intake-changed":
                    await sync.syncPending()
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

            registerIntrospection()
        }
    }

    private func registerIntrospection() {
        let r = IntrospectionRegistry.shared

        // Capture bindings so providers read live values on each request.
        let selectionBinding = $selection
        let backlogSelectionBinding = $backlogSelection
        let librarySelectionBinding = $librarySelection
        let libraryQueryBinding = $libraryQuery
        let inspectorBinding = $inspectorPresented

        // Capture stores by reference (each is @Observable).
        let backlog = backlogStore
        let review = reviewStore
        let author = authorStore
        let library = libraryStore
        let actions = actionQueue

        r.registerState(key: "sidebarSelection") {
            selectionBinding.wrappedValue?.rawValue ?? "<none>"
        }
        r.registerState(key: "backlogSelection") {
            backlogSelectionBinding.wrappedValue ?? "<none>"
        }
        r.registerState(key: "librarySelection") {
            librarySelectionBinding.wrappedValue ?? "<none>"
        }
        r.registerState(key: "libraryQuery") { libraryQueryBinding.wrappedValue }
        r.registerState(key: "inspectorPresented") { inspectorBinding.wrappedValue }

        r.registerState(key: "backlog.count") { backlog.count }
        r.registerState(key: "backlog.entries") { backlog.entries.count }
        r.registerState(key: "backlog.isLoading") { backlog.isLoading }
        r.registerState(key: "review.count") { review.count }
        r.registerState(key: "author.count") { author.count }
        r.registerState(key: "library.count") { library.count }
        r.registerState(key: "library.entries") { library.entries.count }
        r.registerState(key: "library.isLoading") { library.isLoading }
        r.registerState(key: "actions.active") { actions.activeCount }
        r.registerState(key: "actions.failed") { actions.failedCount }

        r.registerAction(id: "select.libraryAll") { @MainActor in
            selectionBinding.wrappedValue = .libraryAll
        }
        r.registerAction(id: "select.backlog") { @MainActor in
            selectionBinding.wrappedValue = .backlog
        }
        r.registerAction(id: "select.maybeReview") { @MainActor in
            selectionBinding.wrappedValue = .maybeReview
        }
        r.registerAction(id: "select.authorProposals") { @MainActor in
            selectionBinding.wrappedValue = .authorProposals
        }
        r.registerAction(id: "inspector.toggle") { @MainActor in
            inspectorBinding.wrappedValue.toggle()
        }
        r.registerAction(id: "inspector.show") { @MainActor in
            inspectorBinding.wrappedValue = true
        }
        r.registerAction(id: "inspector.hide") { @MainActor in
            inspectorBinding.wrappedValue = false
        }
        r.registerAction(id: "library.clearQuery") { @MainActor in
            libraryQueryBinding.wrappedValue = ""
        }
        r.registerAction(id: "library.setQuery") { @MainActor (payload: [String: Any]?) in
            if let q = payload?["query"] as? String {
                libraryQueryBinding.wrappedValue = q
            }
        }
        r.registerAction(id: "backlog.selectByID") { @MainActor (payload: [String: Any]?) in
            if let id = payload?["id"] as? String {
                backlogSelectionBinding.wrappedValue = id
            }
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
        .navigationTitle("Glean")
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .libraryAll:
            LibraryView(store: libraryStore,
                        listState: libraryListState,
                        selection: $librarySelection,
                        query: $libraryQuery)
        case .backlog:
            BacklogView(store: backlogStore,
                        actionQueue: actionQueue,
                        offlineCoordinator: offlineCoordinator,
                        syncPendingOperations: syncPendingOperations,
                        selection: $backlogSelection)
        case .maybeReview:
            MaybeReviewView(store: reviewStore,
                            actionQueue: actionQueue,
                            offlineCoordinator: offlineCoordinator,
                            syncPendingOperations: syncPendingOperations)
        case .authorProposals:
            AuthorProposalsView(store: authorStore,
                                actionQueue: actionQueue,
                                offlineCoordinator: offlineCoordinator,
                                syncPendingOperations: syncPendingOperations)
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
                inspectorPresented: $inspectorPresented,
                query: $libraryQuery
            )
        case .backlog:
            BacklogDetailView(
                entry: selectedBacklogEntry,
                actionQueue: actionQueue,
                offlineCoordinator: offlineCoordinator,
                syncPendingOperations: syncPendingOperations,
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

    private var offlineCoordinator: OfflineIntakeCoordinator {
        OfflineIntakeCoordinator(operationStore: operationStore)
    }

    private func syncPendingOperations() async {
        await syncWorker?.syncPending()
    }
}
