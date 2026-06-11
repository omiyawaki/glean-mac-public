import XCTest
@testable import GleanMac

final class IntakeStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testInitialState() {
        let store = makeBacklogStore()
        XCTAssertEqual(store.entries, [])
        XCTAssertEqual(store.count, 0)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.hasLoadedOnce)
        XCTAssertNil(store.lastRefreshedAt)
    }

    @MainActor
    func testLoadSuccessPopulatesEntriesAndStamps() async {
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"count": 1, "entries": [{
              "added_at":"2026-04-25T08:00:00Z",
              "citekey":"Test",
              "doi":"10.1/x",
              "last_attempt_at":null,
              "title":"T",
              "tried":[]
            }]}
            """
            return Self.ok(request: request, body: body)
        }

        let store = makeBacklogStore()
        await store.load()

        XCTAssertTrue(store.hasLoadedOnce)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.citekey, "Test")
        XCTAssertNil(store.lastError)
        XCTAssertNotNil(store.lastRefreshedAt)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testLoadBypassesURLCache() async {
        var observedCachePolicy: URLRequest.CachePolicy?
        MockURLProtocol.requestHandler = { request in
            observedCachePolicy = request.cachePolicy
            let body = """
            {"count":0,"entries":[]}
            """
            return Self.ok(request: request, body: body)
        }

        let store = makeBacklogStore()
        await store.load()

        XCTAssertEqual(observedCachePolicy, .reloadIgnoringLocalCacheData)
    }

    @MainActor
    func testBacklogFactoryRequestsTrackedScope() async {
        var observedURL: URL?
        MockURLProtocol.requestHandler = { request in
            observedURL = request.url
            let body = """
            {"count":0,"entries":[]}
            """
            return Self.ok(request: request, body: body)
        }

        let store = Stores.backlog()
        await store.load()

        let components = try? XCTUnwrap(URLComponents(
            url: try XCTUnwrap(observedURL),
            resolvingAgainstBaseURL: false
        ))
        XCTAssertEqual(components?.path, "/api/backlog")
        XCTAssertEqual(
            components?.queryItems,
            [URLQueryItem(name: "scope", value: "tracked")]
        )
    }

    @MainActor
    func testLoadHTTPErrorRecordsErrorAndDoesNotMarkLoaded() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let store = makeBacklogStore()
        await store.load()

        XCTAssertFalse(store.hasLoadedOnce)
        XCTAssertEqual(store.entries, [])
        XCTAssertEqual(store.lastError, "HTTP 500")
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testLoadDecodeFailureRecordsError() async {
        MockURLProtocol.requestHandler = { request in
            return Self.ok(request: request, body: "not json at all")
        }

        let store = makeBacklogStore()
        await store.load()

        XCTAssertFalse(store.hasLoadedOnce)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testInitialLoadUsesCachedResponseWhenNetworkFails() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let cached = BacklogResponse(count: 1, entries: [
            BacklogEntry(
                citekey: "Cached2026Paper",
                doi: "10.1000/cached",
                title: "Cached paper",
                addedAt: Date(timeIntervalSince1970: 0),
                lastAttemptAt: nil,
                tried: []
            )
        ])
        let store = makeBacklogStore(loadCachedResponse: { cached })

        await store.load()

        XCTAssertTrue(store.hasLoadedOnce)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.entries.map(\.citekey), ["Cached2026Paper"])
        XCTAssertEqual(store.lastError, "HTTP 503")
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testSuccessfulLoadSavesResponse() async {
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"count":1,"entries":[{
              "added_at":"2026-04-25T08:00:00Z",
              "citekey":"Fresh2026Paper",
              "doi":"10.1000/fresh",
              "last_attempt_at":null,
              "title":"Fresh paper",
              "tried":[]
            }]}
            """
            return Self.ok(request: request, body: body)
        }

        var saved: BacklogResponse?
        let store = makeBacklogStore(saveResponse: { saved = $0 })

        await store.load()

        XCTAssertEqual(saved?.count, 1)
        XCTAssertEqual(saved?.entries.map(\.citekey), ["Fresh2026Paper"])
    }

    @MainActor
    func testSecondLoadSendsETagAndKeepsEntriesOnNotModified() async {
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                let body = """
                {"count":1,"entries":[{
                  "added_at":"2026-04-25T08:00:00Z",
                  "citekey":"CachedByETag",
                  "doi":"10.1000/etag",
                  "last_attempt_at":null,
                  "title":"ETag paper",
                  "tried":[]
                }]}
                """
                let data = Data(body.utf8)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["ETag": "\"v1\""]
                )!
                return (response, data)
            }

            XCTAssertEqual(
                request.value(forHTTPHeaderField: "If-None-Match"),
                "\"v1\""
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 304,
                httpVersion: nil,
                headerFields: ["ETag": "\"v1\""]
            )!
            return (response, Data())
        }

        let store = makeBacklogStore()

        await store.load()
        await store.load(silent: true)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(store.entries.map(\.citekey), ["CachedByETag"])
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testLibraryFactoryLoadsCachedSnapshotBeforeNetworkFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = LibrarySnapshotCache(
            url: directory.appendingPathComponent("library.json")
        )
        try await cache.save(LibraryResponse(count: 1, entries: [
            LibraryEntry(
                citekey: "Cached2026Library",
                title: "Cached library paper",
                year: 2026,
                doi: nil,
                authors: []
            )
        ]))

        let store = Stores.library(snapshotCache: cache)

        await store.load()

        XCTAssertTrue(store.hasLoadedOnce)
        XCTAssertEqual(store.entries.map(\.citekey), ["Cached2026Library"])
        XCTAssertEqual(store.lastError, "HTTP 503")
    }

    @MainActor
    func testLibraryFactoryFallsBackToLocalIndexWhenSnapshotIsMissing() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = LibrarySnapshotCache(
            url: directory.appendingPathComponent("missing.json")
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let db = directory.appendingPathComponent("index.sqlite")
        try Self.runSQLite(db: db, sql: """
        CREATE TABLE records (
          citekey TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          year INTEGER,
          doi TEXT
        );
        CREATE TABLE authors (
          citekey TEXT,
          ord INTEGER,
          family TEXT,
          given TEXT
        );
        INSERT INTO records(citekey, title, year, doi)
          VALUES ('Local2026Index', 'Local index paper', 2026, NULL);
        """)
        let store = Stores.library(
            snapshotCache: cache,
            localIndexReader: LocalLibraryIndexReader(databaseURL: db)
        )

        await store.load()

        XCTAssertTrue(store.hasLoadedOnce)
        XCTAssertEqual(store.entries.map(\.citekey), ["Local2026Index"])
        XCTAssertEqual(store.lastError, "HTTP 503")
    }

    @MainActor
    func testCachedInitialLoadRetriesAfterNetworkFailure() async {
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 503,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, Data())
            }
            let body = """
            {"count":1,"entries":[{
              "added_at":"2026-04-25T08:00:00Z",
              "citekey":"FreshAfterRetry",
              "doi":"10.1000/fresh-after-retry",
              "last_attempt_at":null,
              "title":"Fresh after retry",
              "tried":[]
            }]}
            """
            return Self.ok(request: request, body: body)
        }
        let cached = BacklogResponse(count: 1, entries: [
            BacklogEntry(
                citekey: "StaleCachedPaper",
                doi: "10.1000/stale",
                title: "Stale cached paper",
                addedAt: Date(timeIntervalSince1970: 0),
                lastAttemptAt: nil,
                tried: []
            )
        ])
        let store = makeBacklogStore(
            loadCachedResponse: { cached },
            automaticRetryDelay: .milliseconds(10),
            maxAutomaticRetryAttempts: 2
        )

        await store.load()

        XCTAssertEqual(store.entries.map(\.citekey), ["StaleCachedPaper"])
        XCTAssertEqual(store.lastError, "HTTP 503")

        let deadline = Date().addingTimeInterval(1)
        while requestCount < 2 && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(store.entries.map(\.citekey), ["FreshAfterRetry"])
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testSecondLoadKeepsExistingEntriesUntilNewArrives() async {
        // First load: succeed with one entry.
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"count":1,"entries":[{
              "added_at":"2026-04-25T08:00:00Z","citekey":"a","doi":"10/a",
              "last_attempt_at":null,"title":"a","tried":[]
            }]}
            """
            return Self.ok(request: request, body: body)
        }
        let store = makeBacklogStore()
        await store.load()
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.citekey, "a")

        // Second load: succeed with two different entries.
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"count":2,"entries":[
              {"added_at":"2026-04-25T08:00:00Z","citekey":"b","doi":"10/b",
               "last_attempt_at":null,"title":"b","tried":[]},
              {"added_at":"2026-04-25T08:00:00Z","citekey":"c","doi":"10/c",
               "last_attempt_at":null,"title":"c","tried":[]}
            ]}
            """
            return Self.ok(request: request, body: body)
        }
        await store.load(silent: true)

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.entries.map(\.citekey), ["b", "c"])
    }

    @MainActor
    func testSilentLoadOnAlreadyLoadedStoreDoesNotFlipIsLoading() async {
        // First successful load primes hasLoadedOnce.
        MockURLProtocol.requestHandler = { request in
            return Self.ok(request: request, body: """
            {"count":0,"entries":[]}
            """)
        }
        let store = makeBacklogStore()
        await store.load()
        XCTAssertTrue(store.hasLoadedOnce)

        // Silent reload: by contract, isLoading should never flip true
        // when hasLoadedOnce is already set. We can't observe the
        // transient mid-call value from outside, but we can verify the
        // post-call state is clean.
        await store.load(silent: true)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testOptimisticRemoveFiltersReloadUntilReleased() async {
        // Initial payload contains both items.
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"count":2,"entries":[
              {"added_at":"2026-04-25T08:00:00Z","citekey":"a","doi":"10/a",
               "last_attempt_at":null,"title":"a","tried":[]},
              {"added_at":"2026-04-25T08:00:00Z","citekey":"b","doi":"10/b",
               "last_attempt_at":null,"title":"b","tried":[]}
            ]}
            """
            return Self.ok(request: request, body: body)
        }
        let store = makeBacklogStore()
        await store.load()

        store.optimisticallyRemove(id: "10/a")
        XCTAssertEqual(store.entries.map(\.doi), ["10/b"])
        XCTAssertEqual(store.count, 1)

        await store.load(silent: true)
        XCTAssertEqual(store.entries.map(\.doi), ["10/b"])
        XCTAssertEqual(store.count, 1)

        // --- Root fix verification: self-healing auto-prune ---
        // Simulate the server mutation having landed: the next payload no
        // longer contains "10/a". After this load the optimistic protection
        // for "10/a" must have been automatically pruned (no explicit release).
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"count":1,"entries":[
              {"added_at":"2026-04-25T08:00:00Z","citekey":"b","doi":"10/b",
               "last_attempt_at":null,"title":"b","tried":[]}
            ]}
            """
            return Self.ok(request: request, body: body)
        }
        await store.load(silent: true)
        XCTAssertEqual(store.entries.map(\.doi), ["10/b"])

        // Now simulate a later payload that *does* contain "10/a" again
        // (e.g. a different client re-added it, or a reconcile edge case).
        // Because the previous load pruned the protection, "10/a" must now
        // be visible without any caller having called releaseOptimisticRemoval.
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"count":2,"entries":[
              {"added_at":"2026-04-25T08:00:00Z","citekey":"a","doi":"10/a",
               "last_attempt_at":null,"title":"a","tried":[]},
              {"added_at":"2026-04-25T08:00:00Z","citekey":"b","doi":"10/b",
               "last_attempt_at":null,"title":"b","tried":[]}
            ]}
            """
            return Self.ok(request: request, body: body)
        }
        await store.load(silent: true)
        XCTAssertEqual(store.entries.map(\.doi), ["10/a", "10/b"])
        XCTAssertEqual(store.count, 2)
    }

    @MainActor
    func testOptimisticRemoveIsClearedOnErrorPath() async {
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"count":1,"entries":[
              {"added_at":"2026-04-25T08:00:00Z","citekey":"a","doi":"10/a",
               "last_attempt_at":null,"title":"a","tried":[]}
            ]}
            """
            return Self.ok(request: request, body: body)
        }
        let store = makeBacklogStore()
        await store.load()

        store.optimisticallyRemove(id: "10/a")
        XCTAssertTrue(store.entries.isEmpty)

        // Simulate what the views now do on error: explicitly release + reload
        // so the authoritative (unchanged) server truth reappears.
        store.releaseOptimisticRemoval(id: "10/a")
        await store.load(silent: true)
        XCTAssertEqual(store.entries.map(\.doi), ["10/a"])
    }

    // MARK: - factory

    @MainActor
    private func makeBacklogStore(
        loadCachedResponse: (() async throws -> BacklogResponse?)? = nil,
        saveResponse: ((BacklogResponse) async throws -> Void)? = nil,
        automaticRetryDelay: Duration? = nil,
        maxAutomaticRetryAttempts: Int = 0
    ) -> IntakeStore<BacklogEntry, BacklogResponse> {
        IntakeStore(
            endpoint: URL(string: "http://test.local/api/backlog")!,
            timeoutInterval: 2,
            minSpinnerDuration: .milliseconds(0),  // skip the perceptibility floor in tests
            loadCachedResponse: loadCachedResponse,
            saveResponse: saveResponse,
            automaticRetryDelay: automaticRetryDelay,
            maxAutomaticRetryAttempts: maxAutomaticRetryAttempts,
            extract: { ($0.count, $0.entries) }
        )
    }

    // MARK: - helpers

    private static func ok(request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func runSQLite(db: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [db.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

/// Intercepts URLSession.shared traffic so tests can stub the response
/// without touching the network. Registered globally in setUp/tearDown.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
