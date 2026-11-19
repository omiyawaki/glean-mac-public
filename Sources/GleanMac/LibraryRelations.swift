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

    var apiPathComponent: String {
        switch self {
        case .references: "references"
        case .citedBy: "cited-by"
        }
    }

    var systemImage: String {
        switch self {
        case .references: "text.book.closed"
        case .citedBy: "quote.bubble"
        }
    }
}

struct LibraryRelationRequest: Identifiable, Hashable {
    let source: LibraryEntry
    let kind: LibraryRelationKind

    var id: String { "\(kind.rawValue):\(source.citekey)" }
}

enum LibraryGraphStateName: String, Codable, Sendable {
    case queued
    case running
    case retrying
    case failed
    case unsupported
    case complete
    case empty
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = LibraryGraphStateName(rawValue: value) ?? .unknown
    }
}

struct LibraryGraphState: Codable, Hashable, Sendable {
    let state: LibraryGraphStateName
    let providers: [String]
    let fetchedAt: String?
    let attempts: Int
    let nextAttemptAt: String?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case state, providers, attempts
        case fetchedAt = "fetched_at"
        case nextAttemptAt = "next_attempt_at"
        case lastError = "last_error"
    }

    static let unknown = LibraryGraphState(
        state: .unknown,
        providers: [],
        fetchedAt: nil,
        attempts: 0,
        nextAttemptAt: nil,
        lastError: nil
    )
}

struct LibraryGraphCoverage: Codable, Hashable, Sendable {
    let total: Int?
    let eligible: Int
    let complete: Int
    let empty: Int?
    let queued: Int
    let running: Int?
    let retrying: Int
    let failed: Int
    let unsupported: Int
    let paused: Bool?

    var successfullyIndexed: Int { complete + (empty ?? 0) }
}

struct LibraryRelatedPaper: Identifiable, Hashable, Sendable {
    let target: String
    let citekey: String?
    let title: String
    let year: Int?
    let doi: String?
    let openalexID: String?
    let authorLine: String?
    let isInLibrary: Bool

    var id: String { target }

    var externalURL: URL? {
        if let doiURL = LibraryDOI.url(for: doi) { return doiURL }
        let rawID = openalexID
            ?? (target.lowercased().hasPrefix("openalex:")
                ? String(target.dropFirst("openalex:".count))
                : nil)
        guard let rawID, !rawID.isEmpty else { return nil }
        return URL(string: "https://openalex.org/\(rawID)")
    }
}

struct LibraryRelationResult: Hashable, Sendable {
    let entries: [LibraryRelatedPaper]
    let graph: LibraryGraphState
    let coverage: LibraryGraphCoverage?
    let isOfflineFallback: Bool
}

struct LibraryReferenceEmptyPresentation: Equatable, Sendable {
    let title: String
    let description: String
    let systemImage: String
    let offersRetry: Bool

    init(graph: LibraryGraphState) {
        offersRetry = graph.state == .failed
        switch graph.state {
        case .queued:
            (title, description, systemImage) = (
                "Queued for indexing",
                "References will be fetched by the backend Glean service.",
                "clock"
            )
        case .running:
            (title, description, systemImage) = (
                "Indexing references",
                "OpenAlex or Crossref is being queried now.",
                "arrow.triangle.2.circlepath"
            )
        case .retrying:
            (title, description, systemImage) = (
                "Waiting to retry",
                graph.nextAttemptAt.map { "The next attempt is scheduled for \($0)." }
                    ?? "The provider request will be retried automatically.",
                "clock.arrow.circlepath"
            )
        case .failed:
            (title, description, systemImage) = (
                "Reference indexing failed",
                graph.lastError ?? "Automatic retries were exhausted.",
                "exclamationmark.triangle"
            )
        case .unsupported:
            (title, description, systemImage) = (
                "Automatic lookup unavailable",
                "This paper has no DOI. Manually recorded references remain available, but providers cannot enrich it automatically.",
                "nosign"
            )
        case .empty:
            (title, description, systemImage) = (
                "No references found",
                "The citation providers completed successfully and returned no references.",
                "text.book.closed"
            )
        case .complete:
            (title, description, systemImage) = (
                "No references found",
                "The indexed graph contains no outgoing references.",
                "text.book.closed"
            )
        case .unknown:
            (title, description, systemImage) = (
                "No offline references found",
                "The backend service is unavailable, and the local index cannot distinguish an empty graph from one that has not been indexed.",
                "text.book.closed"
            )
        }
    }
}

private struct LibraryRelationPayload: Decodable {
    let graph: LibraryGraphState
    let coverage: LibraryGraphCoverage?
    let entries: [Entry]

    struct Entry: Decodable {
        let targetID: String
        let citekey: String?
        let title: String?
        let year: Int?
        let doi: String?
        let openalexID: String?
        let authorsFlat: String?
        let inLibrary: Bool

        enum CodingKeys: String, CodingKey {
            case citekey, title, year, doi
            case targetID = "target_id"
            case openalexID = "openalex_id"
            case authorsFlat = "authors_flat"
            case inLibrary = "in_library"
        }

        var relatedPaper: LibraryRelatedPaper {
            LibraryRelatedPaper(
                target: targetID,
                citekey: citekey,
                title: cleaned(title) ?? targetID,
                year: year,
                doi: LibraryDOI.normalized(doi),
                openalexID: cleaned(openalexID),
                authorLine: cleaned(authorsFlat),
                isInLibrary: inLibrary
            )
        }
    }
}

struct LibraryRelationsClient: Sendable {
    let endpoints: GleanBackendEndpoints
    let session: URLSession
    let localReader: LocalLibraryGraphReader

    static let `default` = LibraryRelationsClient()

    init(
        endpoints: GleanBackendEndpoints = .configured,
        session: URLSession = .shared,
        localReader: LocalLibraryGraphReader = .default
    ) {
        self.endpoints = endpoints
        self.session = session
        self.localReader = localReader
    }

    func load(
        kind: LibraryRelationKind,
        source: LibraryEntry,
        libraryEntries: [LibraryEntry]
    ) async throws -> LibraryRelationResult {
        do {
            var request = URLRequest(
                url: endpoints.libraryRelationURL(citekey: source.citekey, kind: kind)
            )
            request.timeoutInterval = 10
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw LoadError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let payload = try JSONDecoder().decode(LibraryRelationPayload.self, from: data)
            return LibraryRelationResult(
                entries: payload.entries.map(\.relatedPaper),
                graph: payload.graph,
                coverage: payload.coverage,
                isOfflineFallback: false
            )
        } catch {
            do {
                return try await localReader.loadResult(
                    kind: kind,
                    source: source,
                    libraryEntries: libraryEntries
                )
            } catch let localError {
                throw LoadError.remoteAndLocal(
                    remote: error.localizedDescription,
                    local: localError.localizedDescription
                )
            }
        }
    }

    func retry(citekey: String) async throws {
        var request = URLRequest(url: endpoints.libraryReferenceRetryURL(citekey: citekey))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 202 else {
            throw LoadError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    enum LoadError: LocalizedError, Equatable {
        case httpStatus(Int)
        case remoteAndLocal(remote: String, local: String)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let status):
                "Glean returned HTTP \(status)."
            case .remoteAndLocal(let remote, let local):
                "The backend Glean service was unavailable (\(remote)), and the offline index couldn't be read (\(local))."
            }
        }
    }
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
        try await loadResult(
            kind: kind,
            source: source,
            libraryEntries: libraryEntries
        ).entries
    }

    func loadResult(
        kind: LibraryRelationKind,
        source: LibraryEntry,
        libraryEntries: [LibraryEntry]
    ) async throws -> LibraryRelationResult {
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
    ) throws -> LibraryRelationResult {
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

        let versioned = try tableExists("citation_edges")
        let entries: [LibraryRelatedPaper]
        if versioned {
            switch kind {
            case .references:
                entries = try versionedOutgoing(source: source)
            case .citedBy:
                entries = try versionedIncoming(source: source)
            }
        } else {
            switch kind {
            case .references:
                entries = try legacyOutgoing(
                    source: source,
                    byCitekey: byCitekey,
                    byDOI: byDOI
                )
            case .citedBy:
                entries = try legacyIncoming(source: source, byCitekey: byCitekey)
            }
        }
        return LibraryRelationResult(
            entries: entries,
            graph: versioned ? (try versionedGraphState(source: source)) : legacyGraphState(
                source: source,
                hasEntries: !entries.isEmpty
            ),
            coverage: nil,
            isOfflineFallback: true
        )
    }

    private func versionedOutgoing(source: GraphSource) throws -> [LibraryRelatedPaper] {
        let rows: [VersionedRow] = try runJSONQuery(
            """
            SELECT e.target_id AS target, lw.citekey, w.title, w.year,
                   w.authors_flat,
                   (SELECT value FROM work_aliases da
                    WHERE da.work_id = w.work_id AND da.kind = 'doi' LIMIT 1) AS doi,
                   (SELECT value FROM work_aliases oa
                    WHERE oa.work_id = w.work_id AND oa.kind = 'openalex' LIMIT 1) AS openalex_id,
                   CASE WHEN lw.citekey IS NULL THEN 0 ELSE 1 END AS in_library
            FROM citation_edges e
            JOIN works w ON w.work_id = e.target_work_id
            LEFT JOIN library_works lw ON lw.work_id = w.work_id
            WHERE e.citekey = \(sqlLiteral(source.citekey))
            ORDER BY e.ord
            """
        )
        return rows.map(\.relatedPaper)
    }

    private func versionedIncoming(source: GraphSource) throws -> [LibraryRelatedPaper] {
        let rows: [VersionedRow] = try runJSONQuery(
            """
            SELECT CASE WHEN r.doi IS NULL THEN 'citekey:' || r.citekey
                        ELSE 'doi:' || r.doi END AS target,
                   r.citekey, r.title, r.year, w.authors_flat, r.doi,
                   (SELECT value FROM work_aliases oa
                    WHERE oa.work_id = source_work.work_id
                      AND oa.kind = 'openalex' LIMIT 1) AS openalex_id,
                   1 AS in_library
            FROM library_works target
            JOIN citation_edges e ON e.target_work_id = target.work_id
            JOIN records r ON r.citekey = e.citekey
            JOIN library_works source_work ON source_work.citekey = r.citekey
            JOIN works w ON w.work_id = source_work.work_id
            WHERE target.citekey = \(sqlLiteral(source.citekey))
            ORDER BY (r.year IS NULL), r.year DESC, r.title, r.citekey
            """
        )
        return rows.map(\.relatedPaper)
    }

    private func legacyOutgoing(
        source: GraphSource,
        byCitekey: [String: GraphPaper],
        byDOI: [String: GraphPaper]
    ) throws -> [LibraryRelatedPaper] {
        let targetRows: [TargetRow] = try runJSONQuery(
            """
            SELECT target FROM outgoing
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
                openalexID: target.lowercased().hasPrefix("openalex:")
                    ? String(target.dropFirst("openalex:".count)) : nil,
                authorLine: cleaned(stub?.authorsFlat),
                isInLibrary: false
            )
        }.sorted(by: newestFirst)
    }

    private func legacyIncoming(
        source: GraphSource,
        byCitekey: [String: GraphPaper]
    ) throws -> [LibraryRelatedPaper] {
        let targets = [source.citekey, LibraryDOI.normalized(source.doi)]
            .compactMap { $0?.lowercased() }
        let literals = targets.map(sqlLiteral).joined(separator: ", ")
        let rows: [CitekeyRow] = try runJSONQuery(
            """
            SELECT DISTINCT citekey FROM outgoing
            WHERE lower(target) IN (\(literals))
            ORDER BY citekey COLLATE NOCASE
            """
        )
        return rows.compactMap { byCitekey[$0.citekey]?.relatedPaper(target: $0.citekey) }
            .sorted(by: newestFirst)
    }

    private func versionedGraphState(source: GraphSource) throws -> LibraryGraphState {
        let rows: [StateRow] = try runJSONQuery(
            """
            SELECT r.doi, r.reference_status, r.reference_providers,
                   r.reference_fetched_at, j.state AS job_state, j.attempts,
                   j.next_attempt_at, j.last_error
            FROM records r LEFT JOIN graph_jobs j ON j.citekey = r.citekey
            WHERE r.citekey = \(sqlLiteral(source.citekey))
            """
        )
        guard let row = rows.first else { return .unknown }
        let state: LibraryGraphStateName
        if let stored = row.referenceStatus,
           let known = LibraryGraphStateName(rawValue: stored) {
            state = known
        } else if row.doi == nil {
            state = .unsupported
        } else if row.jobState == "retry_wait" {
            state = .retrying
        } else if let jobState = row.jobState,
                  let known = LibraryGraphStateName(rawValue: jobState) {
            state = known
        } else {
            state = .queued
        }
        return LibraryGraphState(
            state: state,
            providers: (row.referenceProviders ?? "")
                .split(separator: ",").map(String.init),
            fetchedAt: row.referenceFetchedAt,
            attempts: row.attempts ?? 0,
            nextAttemptAt: row.nextAttemptAt,
            lastError: row.lastError
        )
    }

    private func legacyGraphState(
        source: GraphSource,
        hasEntries: Bool
    ) -> LibraryGraphState {
        let state: LibraryGraphStateName
        if hasEntries { state = .complete }
        else if source.doi == nil { state = .unsupported }
        else { state = .unknown }
        return LibraryGraphState(
            state: state,
            providers: [],
            fetchedAt: nil,
            attempts: 0,
            nextAttemptAt: nil,
            lastError: nil
        )
    }

    private func tableExists(_ table: String) throws -> Bool {
        let rows: [NameRow] = try runJSONQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
                + "AND name = \(sqlLiteral(table))"
        )
        return !rows.isEmpty
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
                openalexID: nil,
                authorLine: authorLine,
                isInLibrary: true
            )
        }
    }

    private struct VersionedRow: Decodable {
        let target: String
        let citekey: String?
        let title: String?
        let year: Int?
        let authorsFlat: String?
        let doi: String?
        let openalexID: String?
        let inLibrary: Int

        enum CodingKeys: String, CodingKey {
            case target, citekey, title, year, doi
            case authorsFlat = "authors_flat"
            case openalexID = "openalex_id"
            case inLibrary = "in_library"
        }

        var relatedPaper: LibraryRelatedPaper {
            LibraryRelatedPaper(
                target: target,
                citekey: citekey,
                title: cleaned(title) ?? target,
                year: year,
                doi: LibraryDOI.normalized(doi),
                openalexID: cleaned(openalexID),
                authorLine: cleaned(authorsFlat),
                isInLibrary: inLibrary != 0
            )
        }
    }

    private struct StateRow: Decodable {
        let doi: String?
        let referenceStatus: String?
        let referenceProviders: String?
        let referenceFetchedAt: String?
        let jobState: String?
        let attempts: Int?
        let nextAttemptAt: String?
        let lastError: String?

        enum CodingKeys: String, CodingKey {
            case doi, attempts
            case referenceStatus = "reference_status"
            case referenceProviders = "reference_providers"
            case referenceFetchedAt = "reference_fetched_at"
            case jobState = "job_state"
            case nextAttemptAt = "next_attempt_at"
            case lastError = "last_error"
        }
    }

    private struct TargetRow: Decodable { let target: String }
    private struct CitekeyRow: Decodable { let citekey: String }
    private struct NameRow: Decodable { let name: String }

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
    let client: LibraryRelationsClient

    @Environment(\.dismiss) private var dismiss
    @State private var result: LibraryRelationResult?
    @State private var isLoading = true
    @State private var error: String?

    init(
        request: LibraryRelationRequest,
        libraryEntries: [LibraryEntry],
        onOpenLibraryPaper: @escaping (String) -> Void,
        client: LibraryRelationsClient = .default
    ) {
        self.request = request
        self.libraryEntries = libraryEntries
        self.onOpenLibraryPaper = onOpenLibraryPaper
        self.client = client
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, result == nil {
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
                } else if let result {
                    relationContent(result)
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
        .task(id: request.id) { await loadAndMonitor() }
    }

    @ViewBuilder
    private func relationContent(_ result: LibraryRelationResult) -> some View {
        if !result.entries.isEmpty {
            List {
                if let message = statusMessage(result) {
                    Section {
                        HStack {
                            Label(message, systemImage: "info.circle")
                            if request.kind == .references,
                               result.graph.state == .failed {
                                Spacer()
                                Button("Retry") { Task { await retryGraph() } }
                            }
                        }
                    }
                }
                ForEach(result.entries) { entry in relationRow(entry) }
            }
        } else if request.kind == .citedBy {
            ContentUnavailableView {
                Label("No citing papers found", systemImage: request.kind.systemImage)
            } description: {
                Text(citedByCoverageDescription(result.coverage))
            }
        } else {
            referenceEmptyState(result.graph)
        }
    }

    @ViewBuilder
    private func referenceEmptyState(_ graph: LibraryGraphState) -> some View {
        let presentation = LibraryReferenceEmptyPresentation(graph: graph)
        if presentation.offersRetry {
            ContentUnavailableView {
                Label(presentation.title, systemImage: presentation.systemImage)
            } description: {
                Text(presentation.description)
            } actions: {
                Button("Retry") { Task { await retryGraph() } }
                    .buttonStyle(.glassProminent)
            }
        } else {
            unavailable(
                presentation.title,
                presentation.description,
                presentation.systemImage
            )
        }
    }

    private func unavailable(_ title: String, _ description: String, _ image: String) -> some View {
        ContentUnavailableView(title, systemImage: image, description: Text(description))
    }

    @ViewBuilder
    private func relationRow(_ entry: LibraryRelatedPaper) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.headline).lineLimit(2)
                Text(detailLine(entry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if entry.isInLibrary, let citekey = entry.citekey {
                Button {
                    onOpenLibraryPaper(citekey)
                    dismiss()
                } label: {
                    Label("Open in Library", systemImage: "arrow.right.circle")
                }
                .labelStyle(.iconOnly)
                .help("Open in Library")
            } else if let url = entry.externalURL {
                Link(destination: url) {
                    Label(entry.doi == nil ? "Open OpenAlex" : "Open DOI",
                          systemImage: "arrow.up.right.square")
                }
                .labelStyle(.iconOnly)
                .help(entry.doi == nil ? "Open in OpenAlex" : "Open DOI in browser")
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

    private func statusMessage(_ result: LibraryRelationResult) -> String? {
        if result.isOfflineFallback {
            return "Showing the local offline citation index."
        }
        if request.kind == .citedBy {
            return citedByCoverageDescription(result.coverage)
        }
        switch result.graph.state {
        case .queued: return "Reference enrichment is queued; showing currently known entries."
        case .running: return "Reference enrichment is running; this list may still change."
        case .retrying: return "Reference enrichment is waiting to retry; showing currently known entries."
        case .failed: return "Reference enrichment failed; showing previously known entries."
        case .unsupported: return "This DOI-less paper can only use manually recorded references."
        default: return nil
        }
    }

    private func citedByCoverageDescription(_ coverage: LibraryGraphCoverage?) -> String {
        guard let coverage else {
            return "Cited By includes only papers in your local Glean library. Backfill coverage is unavailable offline."
        }
        return "Cited By includes only papers in your Glean library. \(coverage.successfullyIndexed) of \(coverage.eligible) DOI-bearing papers have been indexed; \(coverage.queued) queued, \(coverage.retrying) retrying, and \(coverage.failed) failed."
    }

    private func loadAndMonitor() async {
        await load()
        while !Task.isCancelled,
              let result,
              !result.isOfflineFallback,
              [.queued, .running, .retrying].contains(result.graph.state) {
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            await load(showSpinner: false)
        }
    }

    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        error = nil
        defer { isLoading = false }
        do {
            result = try await client.load(
                kind: request.kind,
                source: request.source,
                libraryEntries: libraryEntries
            )
        } catch {
            result = nil
            self.error = error.localizedDescription
        }
    }

    private func retryGraph() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.retry(citekey: request.source.citekey)
            await load(showSpinner: false)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private func cleaned(_ value: String?) -> String? {
    guard let value else { return nil }
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
}

private func newestFirst(_ lhs: LibraryRelatedPaper, _ rhs: LibraryRelatedPaper) -> Bool {
    if lhs.year != rhs.year { return (lhs.year ?? Int.min) > (rhs.year ?? Int.min) }
    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
}
