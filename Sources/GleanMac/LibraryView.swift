import SwiftUI

enum LibraryRowLayout {
    static let rowHeight: CGFloat = 72
}

struct LibraryView: View {
    let store: LibraryStore
    let listState: LibraryListState
    let actionQueue: ActionQueueStore
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void
    let loadedRecord: LibraryRecord?
    let showRelations: (LibraryEntry, LibraryRelationKind) -> Void
    @Binding var selection: String?
    @Binding var query: String

    var body: some View {
        Group {
            if !store.hasLoadedOnce {
                if let message = store.lastError {
                    ContentUnavailableView {
                        Label("Couldn't load library", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { Task { await store.load() } }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ProgressView().controlSize(.large)
                }
            } else {
                let isFiltering = LibraryListIdentity.value(forQuery: query) == "library-filtered"
                ZStack {
                    libraryList(
                        groups: listState.allGrouped,
                        identity: "library-all",
                        isHidden: isFiltering
                    )
                    libraryList(
                        groups: listState.filteredGrouped,
                        identity: "library-filtered",
                        isHidden: !isFiltering
                    )
                }
                .animation(nil, value: isFiltering)
            }
        }
    }

    @ViewBuilder
    private func libraryList(
        groups: [LibraryFilter.YearGroup],
        identity: String,
        isHidden: Bool
    ) -> some View {
        List(selection: $selection) {
            ForEach(groups, id: \.year) { group in
                Section(group.year.map { String($0) } ?? "Undated") {
                    ForEach(group.entries) { entry in
                        LibraryRow(entry: entry,
                                   loadedRecord: loadedRecord,
                                   showRelations: showRelations,
                                   onDropPDFs: { urls in
                                       enqueueForceAttach(urls: urls,
                                                          citekey: entry.citekey)
                                   })
                            .tag(entry.id)
                    }
                }
            }
        }
        .animation(nil, value: groups)
        .id(identity)
        .environment(\.defaultMinListRowHeight, LibraryRowLayout.rowHeight)
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .accessibilityHidden(isHidden)
    }

    @discardableResult
    private func enqueueForceAttach(urls: [URL], citekey: String) -> Bool {
        BacklogPDFDropRouting.enqueueForceAttach(
            urls: urls,
            citekey: citekey,
            actionQueue: actionQueue,
            offlineCoordinator: offlineCoordinator,
            syncPendingOperations: syncPendingOperations
        )
    }
}

private struct LibraryRow: View {
    let entry: LibraryEntry
    let loadedRecord: LibraryRecord?
    let showRelations: (LibraryEntry, LibraryRelationKind) -> Void
    let onDropPDFs: ([URL]) -> Bool
    @State private var isDropTargeted = false
    @State private var actionErrorMessage: String?

    /// Fixed-height rows keep search-clear from triggering thousands of
    /// automatic row-height measurements while still leaving room for a
    /// two-line title plus the author line.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(2)
            Text(authorLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(height: LibraryRowLayout.rowHeight, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear,
                              lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .help(entry.title)
        .contextMenu {
            Button {
                LibraryCopyAction().copyDOI(from: entry)
            } label: {
                Label(LibraryCopyAction.copyDOIMenuTitle, systemImage: "doc.on.doc")
            }
            .disabled(!LibraryCopyAction.canCopyDOI(from: entry))

            Button {
                LibraryCopyAction().copyCiteID(from: entry)
            } label: {
                Label(LibraryCopyAction.copyCiteIDMenuTitle, systemImage: "number")
            }

            Button {
                LibraryExportAction().copyMarkdownCitation(from: entry)
            } label: {
                Label(
                    LibraryExportAction.copyMarkdownCitationMenuTitle,
                    systemImage: "at"
                )
            }

            Button {
                LibraryExportAction().copyMarkdownLink(from: entry)
            } label: {
                Label(
                    LibraryExportAction.copyMarkdownLinkMenuTitle,
                    systemImage: "link"
                )
            }
            .disabled(!LibraryExportAction.canCopyMarkdownLink(from: entry))

            Button {
                Task {
                    await LibraryExportAction().copyBibTeX(
                        from: entry,
                        loadedRecord: loadedRecord
                    )
                }
            } label: {
                Label(LibraryExportAction.copyBibTeXMenuTitle, systemImage: "curlybraces")
            }

            Menu {
                ForEach(LibraryCitationStyle.allCases) { style in
                    Button(style.menuTitle) {
                        Task {
                            await LibraryCopyAction().copyCitation(
                                from: entry,
                                loadedRecord: loadedRecord,
                                style: style
                            )
                        }
                    }
                }
            } label: {
                Label(LibraryCopyAction.copyCitationMenuTitle, systemImage: "text.quote")
            }

            Divider()

            Button {
                LibraryExternalLinkAction().openDOI(from: entry)
            } label: {
                Label(
                    LibraryExternalLinkAction.openDOIMenuTitle,
                    systemImage: "arrow.up.right.square"
                )
            }
            .disabled(!LibraryExternalLinkAction.canOpenDOI(from: entry))

            Button {
                Task {
                    do {
                        try await LibraryPaperFileAction().openPDF(
                            for: entry,
                            loadedRecord: loadedRecord
                        )
                    } catch {
                        actionErrorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label(LibraryPaperFileAction.openPDFMenuTitle, systemImage: "doc.richtext")
            }
            .disabled(LibraryPaperFileAction.hasKnownPDF(
                for: entry,
                loadedRecord: loadedRecord
            ) == false)

            Button {
                Task {
                    do {
                        try await LibraryPaperFileAction().revealPDF(
                            for: entry,
                            loadedRecord: loadedRecord
                        )
                    } catch {
                        actionErrorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label(
                    LibraryPaperFileAction.revealPDFMenuTitle,
                    systemImage: "folder"
                )
            }
            .disabled(LibraryPaperFileAction.hasKnownPDF(
                for: entry,
                loadedRecord: loadedRecord
            ) == false)

            Divider()

            ForEach([LibraryRelationKind.references, .citedBy]) { kind in
                Button {
                    showRelations(entry, kind)
                } label: {
                    Label(kind.menuTitle, systemImage: kind.systemImage)
                }
            }
        }
        .alert(
            "Paper action failed",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .dropDestination(for: URL.self) { urls, _ in
            onDropPDFs(urls)
        } isTargeted: { isDropTargeted = $0 }
    }

    private var authorLine: String {
        let names = entry.authors.map { $0.family }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return "\(names[0]) et al."
        }
    }
}
