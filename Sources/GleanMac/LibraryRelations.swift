import Foundation
import SwiftUI

enum LibraryRelationKind: String, Identifiable, Sendable {
    case references
    case citedBy

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .references: "Show References"
        case .citedBy: "Show Cited By"
        }
    }

    var navigationTitle: String {
        switch self {
        case .references: "References"
        case .citedBy: "Cited By"
        }
    }

    var systemImage: String {
        switch self {
        case .references: "text.book.closed"
        case .citedBy: "quote.bubble"
        }
    }

    var emptyTitle: String {
        switch self {
        case .references: "No references indexed"
        case .citedBy: "No citing papers found"
        }
    }

    var emptyDescription: String {
        switch self {
        case .references:
            "Run glean graph fetch for this paper to populate its citation graph."
        case .citedBy:
            "No indexed library records cite this paper by DOI or Cite ID."
        }
    }
}

struct LibraryRelationRequest: Identifiable, Hashable {
    let source: LibraryEntry
    let kind: LibraryRelationKind

    var id: String { "\(kind.rawValue):\(source.citekey)" }
}

struct LibraryRelatedPaper: Identifiable, Hashable, Sendable {
    let target: String
    let citekey: String?
    let title: String
    let year: Int?
    let doi: String?
    let authorLine: String?

    var id: String { target }
    var isInLibrary: Bool { citekey != nil }
}

struct LocalLibraryGraphReader: Sendable {
    let databaseURL: URL
    let sqliteExecutableURL: URL

    static let `default` = LocalLibraryGraphReader(
        databaseURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/glean/index.sqlite"),
        sqliteExecutableURL: URL(fileURLWithPath: "/usr/bin/sqlite3")
    )

    init(
        databaseURL: URL,
        sqliteExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    ) {
        self.databaseURL = databaseURL
        self.sqliteExecutableURL = sqliteExecutableURL
    }

    func load(
        kind: LibraryRelationKind,
        source: LibraryEntry,
        libraryEntries: [LibraryEntry]
    ) async throws -> [LibraryRelatedPaper] {
        let source = GraphSource(citekey: source.citekey, doi: source.doi)
        let papers = libraryEntries.map(GraphPaper.init)
        return try await Task.detached(priority: .userInitiated) {
            try loadSynchronously(kind: kind, source: source, libraryEntries: papers)
        }.value
    }

    private func loadSynchronously(
        kind: LibraryRelationKind,
        source: GraphSource,
        libraryEntries: [GraphPaper]
    ) throws -> [LibraryRelatedPaper] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw ReadError.indexMissing
        }
        var byCitekey: [String: GraphPaper] = [:]
        var byDOI: [String: GraphPaper] = [:]
        for paper in libraryEntries {
            byCitekey[paper.citekey] = paper
            if let doi = LibraryDOI.normalized(paper.doi)?.lowercased(), byDOI[doi] == nil {
                byDOI[doi] = paper
            }
        }
        let results: [LibraryRelatedPaper]
        switch kind {
        case .references:
            results = try outgoing(
                source: source,
                byCitekey: byCitekey,
                byDOI: byDOI
            )
        case .citedBy:
            results = try incoming(
                source: source,
                byCitekey: byCitekey
            )
        }
        return results.sorted {
            if $0.year != $1.year { return ($0.year ?? Int.min) > ($1.year ?? Int.min) }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func outgoing(
        source: GraphSource,
        byCitekey: [String: GraphPaper],
        byDOI: [String: GraphPaper]
    ) throws -> [LibraryRelatedPaper] {
        let targetRows: [TargetRow] = try runJSONQuery(
            """
            SELECT target
            FROM outgoing
            WHERE citekey = \(sqlLiteral(source.citekey))
            ORDER BY target COLLATE NOCASE
            """
        )
        let targets = targetRows.map(\.target)
        guard !targets.isEmpty else { return [] }
        let literals = targets.map(sqlLiteral).joined(separator: ", ")
        let stubRows: [StubRow] = try runJSONQuery(
            """
            SELECT doi, citekey, title, year, authors_flat
            FROM stubs
            WHERE doi IN (\(literals)) OR citekey IN (\(literals))
            """
        )
        var stubsByTarget: [String: StubRow] = [:]
        for stub in stubRows {
            if let citekey = stub.citekey { stubsByTarget[citekey] = stub }
            if let doi = LibraryDOI.normalized(stub.doi) {
                stubsByTarget[doi.lowercased()] = stub
            }
        }
        return targets.map { target in
            if let paper = byCitekey[target]
                ?? LibraryDOI.normalized(target).flatMap({ byDOI[$0.lowercased()] }) {
                return paper.relatedPaper(target: target)
            }
            let normalizedTarget = LibraryDOI.normalized(target)
            let stub = stubsByTarget[target]
                ?? normalizedTarget.flatMap { stubsByTarget[$0.lowercased()] }
            return LibraryRelatedPaper(
                target: target,
                citekey: nil,
                title: cleaned(stub?.title) ?? target,
                year: stub?.year,
                doi: LibraryDOI.normalized(stub?.doi)
                    ?? (target.contains("/") ? normalizedTarget : nil),
                authorLine: cleaned(stub?.authorsFlat)
            )
        }
    }

    private func incoming(
        source: GraphSource,
        byCitekey: [String: GraphPaper]
    ) throws -> [LibraryRelatedPaper] {
        let targets = [source.citekey, LibraryDOI.normalized(source.doi)]
            .compactMap { $0?.lowercased() }
        let literals = targets.map(sqlLiteral).joined(separator: ", ")
        let rows: [CitekeyRow] = try runJSONQuery(
            """
            SELECT DISTINCT citekey
            FROM outgoing
            WHERE lower(target) IN (\(literals))
            ORDER BY citekey COLLATE NOCASE
            """
        )
        return rows.compactMap { row in
            byCitekey[row.citekey]?.relatedPaper(target: row.citekey)
        }
    }

    private func runJSONQuery<T: Decodable>(_ sql: String) throws -> [T] {
        let process = Process()
        process.executableURL = sqliteExecutableURL
        process.arguments = ["-json", databaseURL.path, sql]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "sqlite3 failed"
            throw ReadError.sqlite(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if data.isEmpty || data.allSatisfy({ [0x0a, 0x0d, 0x20, 0x09].contains($0) }) {
            return []
        }
        return try JSONDecoder().decode([T].self, from: data)
    }

    private func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    enum ReadError: LocalizedError, Equatable {
        case indexMissing
        case sqlite(String)

        var errorDescription: String? {
            switch self {
            case .indexMissing:
                "The local Glean citation index isn't available on this Mac."
            case .sqlite(let detail):
                "The local Glean citation index couldn't be read: \(detail)"
            }
        }
    }

    private struct GraphSource: Sendable {
        let citekey: String
        let doi: String?
    }

    private struct GraphPaper: Sendable {
        let citekey: String
        let title: String
        let year: Int?
        let doi: String?
        let authorLine: String?

        init(_ entry: LibraryEntry) {
            citekey = entry.citekey
            title = entry.title
            year = entry.year
            doi = entry.doi
            let families = entry.authors.map(\.family).filter { !$0.isEmpty }
            switch families.count {
            case 0: authorLine = nil
            case 1: authorLine = families[0]
            case 2: authorLine = "\(families[0]) & \(families[1])"
            default: authorLine = "\(families[0]) et al."
            }
        }

        func relatedPaper(target: String) -> LibraryRelatedPaper {
            LibraryRelatedPaper(
                target: target,
                citekey: citekey,
                title: title,
                year: year,
                doi: LibraryDOI.normalized(doi),
                authorLine: authorLine
            )
        }
    }

    private struct TargetRow: Decodable {
        let target: String
    }

    private struct CitekeyRow: Decodable {
        let citekey: String
    }

    private struct StubRow: Decodable {
        let doi: String?
        let citekey: String?
        let title: String?
        let year: Int?
        let authorsFlat: String?

        enum CodingKeys: String, CodingKey {
            case doi, citekey, title, year
            case authorsFlat = "authors_flat"
        }
    }
}

struct LibraryRelationsView: View {
    let request: LibraryRelationRequest
    let libraryEntries: [LibraryEntry]
    let onOpenLibraryPaper: (String) -> Void
    let reader: LocalLibraryGraphReader

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LibraryRelatedPaper] = []
    @State private var isLoading = true
    @State private var error: String?

    init(
        request: LibraryRelationRequest,
        libraryEntries: [LibraryEntry],
        onOpenLibraryPaper: @escaping (String) -> Void,
        reader: LocalLibraryGraphReader = .default
    ) {
        self.request = request
        self.libraryEntries = libraryEntries
        self.onOpenLibraryPaper = onOpenLibraryPaper
        self.reader = reader
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().controlSize(.large)
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't load citation graph", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.glassProminent)
                    }
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        request.kind.emptyTitle,
                        systemImage: request.kind.systemImage,
                        description: Text(request.kind.emptyDescription)
                    )
                } else {
                    List(entries) { entry in
                        relationRow(entry)
                    }
                }
            }
            .navigationTitle(request.kind.navigationTitle)
            .navigationSubtitle(request.source.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 420, idealHeight: 520)
        .task(id: request.id) { await load() }
    }

    @ViewBuilder
    private func relationRow(_ entry: LibraryRelatedPaper) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(detailLine(entry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let citekey = entry.citekey {
                Button {
                    onOpenLibraryPaper(citekey)
                    dismiss()
                } label: {
                    Label("Open in Library", systemImage: "arrow.right.circle")
                }
                .labelStyle(.iconOnly)
                .help("Open in Library")
            } else if let url = LibraryDOI.url(for: entry.doi) {
                Link(destination: url) {
                    Label("Open DOI", systemImage: "arrow.up.right.square")
                }
                .labelStyle(.iconOnly)
                .help("Open DOI in browser")
            }
        }
        .padding(.vertical, 4)
    }

    private func detailLine(_ entry: LibraryRelatedPaper) -> String {
        [entry.authorLine, entry.year.map(String.init), entry.doi]
            .compactMap { value in
                let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? nil : value
            }
            .joined(separator: " · ")
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            entries = try await reader.load(
                kind: request.kind,
                source: request.source,
                libraryEntries: libraryEntries
            )
        } catch {
            entries = []
            self.error = error.localizedDescription
        }
    }
}
