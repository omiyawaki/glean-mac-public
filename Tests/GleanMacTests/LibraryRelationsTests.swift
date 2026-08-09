import XCTest
@testable import GleanMac

final class LibraryRelationsTests: XCTestCase {
    override func tearDown() {
        RelationURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoadsReferencesFromLibraryAndExternalStubs() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let reader = LocalLibraryGraphReader(databaseURL: fixture)
        let entries = makeLibraryEntries()

        let related = try await reader.load(
            kind: .references,
            source: entries[0],
            libraryEntries: entries
        )

        XCTAssertEqual(
            related.map(\.title),
            ["Related library paper", "External citekey paper", "External DOI paper"]
        )
        XCTAssertEqual(related[0].citekey, "Related2023")
        XCTAssertEqual(related[0].doi, "10.1000/library")
        XCTAssertNil(related[1].citekey)
        XCTAssertEqual(related[1].authorLine, "External, E.")
        XCTAssertEqual(related[2].doi, "10.2000/stub")
    }

    func testLoadsCitingPapersBySourceDOIOrCitekey() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let reader = LocalLibraryGraphReader(databaseURL: fixture)
        let entries = makeLibraryEntries()

        let related = try await reader.load(
            kind: .citedBy,
            source: entries[0],
            libraryEntries: entries
        )

        XCTAssertEqual(related.map(\.citekey), ["CitingByDOI", "CitingByCitekey"])
        XCTAssertTrue(related.allSatisfy(\.isInLibrary))
    }

    func testMissingIndexReportsActionableError() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let reader = LocalLibraryGraphReader(databaseURL: missing)

        do {
            _ = try await reader.load(
                kind: .references,
                source: makeLibraryEntries()[0],
                libraryEntries: []
            )
            XCTFail("Expected a missing-index error")
        } catch {
            XCTAssertEqual(error as? LocalLibraryGraphReader.ReadError, .indexMissing)
        }
    }

    func testReferenceLookupStaysWithinInteractionBudgetForLargeLibrary() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let reader = LocalLibraryGraphReader(databaseURL: fixture)
        let source = makeLibraryEntries()[0]
        let entries = (0..<5_000).map { index in
            LibraryEntry(
                citekey: "Paper\(index)",
                title: "Paper \(index)",
                year: 2026 - (index % 30),
                doi: "10.5555/paper.\(index)",
                authors: []
            )
        } + makeLibraryEntries()

        let start = Date()
        _ = try await reader.load(kind: .references, source: source, libraryEntries: entries)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1, "citation lookup took \(elapsed)s")
    }

    func testVersionedOfflineReaderPreservesBibliographyOrderAndMetadata() async throws {
        let fixture = try makeVersionedFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let reader = LocalLibraryGraphReader(databaseURL: fixture)
        let source = makeLibraryEntries()[0]

        let result = try await reader.loadResult(
            kind: .references,
            source: source,
            libraryEntries: makeLibraryEntries()
        )

        XCTAssertEqual(result.entries.map(\.target), [
            "openalex:W200",
            "doi:10.1000/library",
        ])
        XCTAssertEqual(result.entries[0].title, "External first in bibliography")
        XCTAssertEqual(result.entries[0].openalexID, "W200")
        XCTAssertEqual(result.entries[0].externalURL?.absoluteString,
                       "https://openalex.org/W200")
        XCTAssertTrue(result.entries[1].isInLibrary)
        XCTAssertEqual(result.graph.state, .complete)
        XCTAssertTrue(result.isOfflineFallback)
    }

    func testVersionedOfflineReaderLoadsReverseEdgesFromLibraryOnly() async throws {
        let fixture = try makeVersionedFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let reader = LocalLibraryGraphReader(databaseURL: fixture)

        let result = try await reader.loadResult(
            kind: .citedBy,
            source: makeLibraryEntries()[0],
            libraryEntries: makeLibraryEntries()
        )

        XCTAssertEqual(result.entries.map(\.citekey), ["Citer2025"])
        XCTAssertTrue(result.entries.allSatisfy(\.isInLibrary))
    }

    func testAPIIsPrimaryAndDecodesCoverageAndOpenAlexTargets() async throws {
        let session = makeMockSession()
        RelationURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.path,
                "/api/papers/Source2024/references"
            )
            return Self.response(
                request: request,
                status: 200,
                body: """
                {
                  "source":{"citekey":"Source2024","title":"Source paper","year":2024,"doi":"10.9999/source"},
                  "relation":"references",
                  "count":1,
                  "graph":{"state":"complete","providers":["openalex"],"fetched_at":"2026-08-09","attempts":0,"next_attempt_at":null,"last_error":null},
                  "coverage":{"total":10,"eligible":8,"complete":5,"empty":1,"queued":1,"running":0,"retrying":1,"failed":0,"unsupported":2,"paused":false},
                  "entries":[{"target_id":"openalex:W200","citekey":null,"title":"External API paper","year":2020,"doi":null,"openalex_id":"W200","authors_flat":"External E.","in_library":false}]
                }
                """
            )
        }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let client = LibraryRelationsClient(
            endpoints: testEndpoints,
            session: session,
            localReader: LocalLibraryGraphReader(databaseURL: missing)
        )

        let result = try await client.load(
            kind: .references,
            source: makeLibraryEntries()[0],
            libraryEntries: makeLibraryEntries()
        )

        XCTAssertFalse(result.isOfflineFallback)
        XCTAssertEqual(result.graph.state, .complete)
        XCTAssertEqual(result.coverage?.successfullyIndexed, 6)
        XCTAssertEqual(result.entries[0].externalURL?.absoluteString,
                       "https://openalex.org/W200")
    }

    func testClientFallsBackToLegacyIndexWhenAPIIsUnavailable() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let session = makeMockSession()
        RelationURLProtocol.requestHandler = { request in
            Self.response(request: request, status: 503, body: "{}")
        }
        let client = LibraryRelationsClient(
            endpoints: testEndpoints,
            session: session,
            localReader: LocalLibraryGraphReader(databaseURL: fixture)
        )

        let result = try await client.load(
            kind: .references,
            source: makeLibraryEntries()[0],
            libraryEntries: makeLibraryEntries()
        )

        XCTAssertTrue(result.isOfflineFallback)
        XCTAssertEqual(result.entries.count, 3)
    }

    func testRetryUsesIdempotentPOSTEndpoint() async throws {
        let session = makeMockSession()
        RelationURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.path,
                "/api/papers/Source2024/references/retry"
            )
            return Self.response(request: request, status: 202, body: "{}")
        }
        let client = LibraryRelationsClient(
            endpoints: testEndpoints,
            session: session,
            localReader: .default
        )

        try await client.retry(citekey: "Source2024")
    }

    func testReferenceSheetHasDistinctOperationalAndTerminalPresentations() {
        let cases: [(LibraryGraphStateName, String)] = [
            (.queued, "Queued for indexing"),
            (.running, "Indexing references"),
            (.retrying, "Waiting to retry"),
            (.failed, "Reference indexing failed"),
            (.unsupported, "Automatic lookup unavailable"),
            (.empty, "No references found"),
            (.complete, "No references found"),
            (.unknown, "No offline references found"),
        ]

        for (state, expectedTitle) in cases {
            let presentation = LibraryReferenceEmptyPresentation(
                graph: LibraryGraphState(
                    state: state,
                    providers: [],
                    fetchedAt: nil,
                    attempts: state == .failed ? 6 : 0,
                    nextAttemptAt: state == .retrying ? "2026-08-09T12:05:00Z" : nil,
                    lastError: state == .failed ? "provider unavailable" : nil
                )
            )
            XCTAssertEqual(presentation.title, expectedTitle)
            XCTAssertEqual(presentation.offersRetry, state == .failed)
        }

        let empty = LibraryReferenceEmptyPresentation(
            graph: graphState(.empty)
        )
        let complete = LibraryReferenceEmptyPresentation(
            graph: graphState(.complete)
        )
        XCTAssertNotEqual(empty.description, complete.description)
    }

    private func makeFixture() throws -> URL {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            CREATE TABLE outgoing (
              citekey TEXT NOT NULL,
              target TEXT NOT NULL,
              PRIMARY KEY (citekey, target)
            );
            CREATE TABLE stubs (
              doi TEXT UNIQUE,
              citekey TEXT UNIQUE,
              title TEXT,
              year INTEGER,
              authors_flat TEXT
            );
            INSERT INTO outgoing VALUES ('Source2024', '10.1000/library');
            INSERT INTO outgoing VALUES ('Source2024', 'ExternalCitekey');
            INSERT INTO outgoing VALUES ('Source2024', '10.2000/stub');
            INSERT INTO outgoing VALUES ('CitingByDOI', '10.9999/source');
            INSERT INTO outgoing VALUES ('CitingByCitekey', 'Source2024');
            INSERT INTO stubs(doi, title, year, authors_flat)
              VALUES ('10.2000/stub', 'External DOI paper', 2021, 'Stub, S.');
            INSERT INTO stubs(citekey, title, year, authors_flat)
              VALUES ('ExternalCitekey', 'External citekey paper', 2022, 'External, E.');
            """
        )
        return databaseURL
    }

    private func makeVersionedFixture() throws -> URL {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            CREATE TABLE records (
              citekey TEXT PRIMARY KEY, title TEXT, year INTEGER, doi TEXT,
              reference_status TEXT, reference_providers TEXT,
              reference_fetched_at TEXT
            );
            CREATE TABLE works (
              work_id INTEGER PRIMARY KEY, title TEXT, year INTEGER,
              authors_flat TEXT
            );
            CREATE TABLE work_aliases (
              kind TEXT, value TEXT, normalized_value TEXT, work_id INTEGER
            );
            CREATE TABLE library_works (citekey TEXT PRIMARY KEY, work_id INTEGER);
            CREATE TABLE citation_edges (
              citekey TEXT, ord INTEGER, target_work_id INTEGER, target_id TEXT
            );
            CREATE TABLE graph_jobs (
              citekey TEXT, state TEXT, attempts INTEGER, next_attempt_at TEXT,
              last_error TEXT
            );

            INSERT INTO records VALUES
              ('Source2024', 'Source paper', 2024, '10.9999/source',
               'complete', 'openalex', '2026-08-09'),
              ('Related2023', 'Related library paper', 2023, '10.1000/library',
               NULL, NULL, NULL),
              ('Citer2025', 'Citing paper', 2025, '10.3000/citer',
               'complete', 'openalex', '2026-08-09');
            INSERT INTO works VALUES
              (1, 'Source paper', 2024, 'Source S.'),
              (2, 'External first in bibliography', 1990, 'External E.'),
              (3, 'Related library paper', 2023, 'Related R.'),
              (4, 'Citing paper', 2025, 'Citer C.');
            INSERT INTO work_aliases VALUES
              ('doi', '10.9999/source', '10.9999/source', 1),
              ('citekey', 'Source2024', 'Source2024', 1),
              ('openalex', 'W200', 'W200', 2),
              ('doi', '10.1000/library', '10.1000/library', 3),
              ('citekey', 'Related2023', 'Related2023', 3),
              ('doi', '10.3000/citer', '10.3000/citer', 4),
              ('citekey', 'Citer2025', 'Citer2025', 4);
            INSERT INTO library_works VALUES
              ('Source2024', 1), ('Related2023', 3), ('Citer2025', 4);
            INSERT INTO citation_edges VALUES
              ('Source2024', 0, 2, 'openalex:W200'),
              ('Source2024', 1, 3, 'doi:10.1000/library'),
              ('Citer2025', 0, 1, 'doi:10.9999/source');
            """
        )
        return databaseURL
    }

    private func makeLibraryEntries() -> [LibraryEntry] {
        [
            LibraryEntry(
                citekey: "Source2024",
                title: "Source paper",
                year: 2024,
                doi: "10.9999/source",
                authors: [LibraryAuthor(family: "Source", given: "S.")]
            ),
            LibraryEntry(
                citekey: "Related2023",
                title: "Related library paper",
                year: 2023,
                doi: "10.1000/library",
                authors: [LibraryAuthor(family: "Related", given: "R.")]
            ),
            LibraryEntry(
                citekey: "CitingByDOI",
                title: "Cites by DOI",
                year: 2025,
                doi: nil,
                authors: []
            ),
            LibraryEntry(
                citekey: "CitingByCitekey",
                title: "Cites by citekey",
                year: 2020,
                doi: nil,
                authors: []
            ),
        ]
    }

    private func runSQLite(databaseURL: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private var testEndpoints: GleanBackendEndpoints {
        GleanBackendEndpoints(
            intakeBase: URL(string: "http://127.0.0.1:8765")!,
            libraryBase: URL(string: "http://127.0.0.1:8766")!
        )
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelationURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func graphState(_ state: LibraryGraphStateName) -> LibraryGraphState {
        LibraryGraphState(
            state: state,
            providers: [],
            fetchedAt: nil,
            attempts: 0,
            nextAttemptAt: nil,
            lastError: nil
        )
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }
}

private final class RelationURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (
        (URLRequest) throws -> (HTTPURLResponse, Data)
    )?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
