import AppleAppDesignSystem
import SwiftUI
import os

private let libraryRailLog = Logger(
    subsystem: "com.miyawaki.glean-mac",
    category: "library-rail"
)

enum LibraryRowLayout {
    static let rowHeight: CGFloat = 72
    static let separatorHeight: CGFloat = 1
    static let sectionHeaderHeight: CGFloat = 34
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
    @State private var allScrollController = IndexedNativeScrollController()
    @State private var filteredScrollController = IndexedNativeScrollController()
    @State private var allRailJumpStarted: ContinuousClock.Instant?
    @State private var filteredRailJumpStarted: ContinuousClock.Instant?
    @State private var actionErrorMessage: String?

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
                        rows: listState.allRows,
                        chronology: listState.allChronology,
                        destinationPositions: listState.allDestinationPositions,
                        identity: "library-all",
                        isHidden: isFiltering,
                        scrollController: allScrollController,
                        railJumpStarted: $allRailJumpStarted
                    )
                    libraryList(
                        rows: listState.filteredRows,
                        chronology: listState.filteredChronology,
                        destinationPositions: listState.filteredDestinationPositions,
                        identity: "library-filtered",
                        isHidden: !isFiltering,
                        scrollController: filteredScrollController,
                        railJumpStarted: $filteredRailJumpStarted
                    )
                }
                .animation(nil, value: isFiltering)
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
    }

    @ViewBuilder
    private func libraryList(
        rows: [LibraryListRow],
        chronology: [LibraryChronology.Marker],
        destinationPositions: [String: Double],
        identity: String,
        isHidden: Bool,
        scrollController: IndexedNativeScrollController,
        railJumpStarted: Binding<ContinuousClock.Instant?>
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                IndexedNativeScrollTargetReader(controller: scrollController)
                    .frame(height: 0)

                ForEach(rows) { row in
                    switch row {
                    case .header(_, let title):
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: LibraryRowLayout.sectionHeaderHeight,
                                alignment: .leading
                            )
                            .background(.bar)
                            .accessibilityAddTraits(.isHeader)

                    case .paper(let entry):
                        VStack(spacing: 0) {
                            LibraryRow(entry: entry,
                                       loadedRecord: loadedRecord,
                                       showRelations: showRelations,
                                       reportActionError: { message in
                                           actionErrorMessage = message
                                       },
                                       onDropPDFs: { urls in
                                           enqueueForceAttach(urls: urls,
                                                              citekey: entry.citekey)
                                       })
                                .background {
                                    if selection == entry.id {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.22))
                                            .padding(.horizontal, 5)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection = entry.id
                                }
                                .accessibilityAddTraits(
                                    selection == entry.id ? .isSelected : []
                                )

                            Divider()
                                .padding(.leading, 12)
                                .frame(height: LibraryRowLayout.separatorHeight)
                        }
                        .frame(
                            height: LibraryRowLayout.rowHeight
                                + LibraryRowLayout.separatorHeight
                        )
                        .id(entry.citekey)
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldOffset, newOffset in
            guard oldOffset != newOffset,
                  let started = railJumpStarted.wrappedValue else { return }
            railJumpStarted.wrappedValue = nil
            let milliseconds = (ContinuousClock.now - started) / .milliseconds(1)
            libraryRailLog.notice(
                "rail first-frame response ms=\(milliseconds, privacy: .public)"
            )
        }
        .overlay(alignment: .trailing) {
            if chronology.count > 1 {
                IndexedScrollRail(
                    markers: chronology.map {
                        IndexedScrollRailMarker(
                            id: $0.id,
                            label: $0.label,
                            majorLabel: $0.majorLabel,
                            destinationPosition: $0.contentPosition
                        )
                    },
                    tickStrideCandidates: [1, 3, 6, 12, 24, 60, 120, 240, 600],
                    // One base tick per publication year. Hover magnification
                    // reveals the twelve monthly positions between them.
                    minimumTickStride: 12,
                    tickAlignment: chronology.firstIndex(where: \.isYearBoundary) ?? 0,
                    onSelect: { marker in
                        guard let destinationPosition = marker.destinationPosition else {
                            return
                        }
                        jump(
                            to: destinationPosition,
                            scrollController: scrollController,
                            railJumpStarted: railJumpStarted,
                            measureResponse: true
                        )
                    }
                )
                .padding(.vertical, 12)
                // Keep the fast-scroll rail beside, rather than beneath, the
                // system scrollbar and its top/bottom end furniture.
                .padding(.trailing, 22)
            }
        }
        .onChange(of: selection) { _, citekey in
            guard let citekey,
                  let position = destinationPositions[citekey] else { return }
            jump(
                to: position,
                scrollController: scrollController,
                railJumpStarted: railJumpStarted,
                measureResponse: false
            )
        }
        .animation(nil, value: rows)
        .id(identity)
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .accessibilityHidden(isHidden)
    }

    private func jump(
        to contentPosition: Double,
        scrollController: IndexedNativeScrollController,
        railJumpStarted: Binding<ContinuousClock.Instant?>,
        measureResponse: Bool
    ) {
        if measureResponse {
            railJumpStarted.wrappedValue = ContinuousClock.now
        }
        guard scrollController.scroll(toContentPosition: contentPosition) else {
            railJumpStarted.wrappedValue = nil
            libraryRailLog.error("native rail scroll target unavailable")
            return
        }
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
    let reportActionError: (String) -> Void
    let onDropPDFs: ([URL]) -> Bool
    @State private var isDropTargeted = false

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
                        reportActionError(error.localizedDescription)
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
                        reportActionError(error.localizedDescription)
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
