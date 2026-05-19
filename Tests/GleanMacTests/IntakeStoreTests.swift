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

        store.releaseOptimisticRemoval(id: "10/a")
        await store.load(silent: true)
        XCTAssertEqual(store.entries.map(\.doi), ["10/a", "10/b"])
        XCTAssertEqual(store.count, 2)
    }

    // MARK: - factory

    @MainActor
    private func makeBacklogStore(
        loadCachedResponse: (() async throws -> BacklogResponse?)? = nil,
        saveResponse: ((BacklogResponse) async throws -> Void)? = nil
    ) -> IntakeStore<BacklogEntry, BacklogResponse> {
        IntakeStore(
            endpoint: URL(string: "http://test.local/api/backlog")!,
            timeoutInterval: 2,
            minSpinnerDuration: .milliseconds(0),  // skip the perceptibility floor in tests
            loadCachedResponse: loadCachedResponse,
            saveResponse: saveResponse,
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
