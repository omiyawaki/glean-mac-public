import XCTest
@testable import GleanMac

final class LibraryDetailStoreTests: XCTestCase {
    @MainActor
    func testNewestSelectionWinsWhenAnEarlierLoadFinishesLater() async throws {
        let store = LibraryDetailStore(recordCache: temporaryCache()) { citekey in
            if citekey == "first" {
                try await Task.sleep(for: .milliseconds(100))
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
            return self.makeRecord(citekey: citekey)
        }

        let firstLoad = Task { await store.load(citekey: "first") }
        try await Task.sleep(for: .milliseconds(10))
        let secondLoad = Task { await store.load(citekey: "second") }

        await secondLoad.value
        await firstLoad.value

        XCTAssertEqual(store.loadedCitekey, "second")
        XCTAssertEqual(store.record?.citekey, "second")
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.error)
    }

    @MainActor
    func testCancelledLoadDoesNotPublishAnError() async throws {
        let store = LibraryDetailStore(recordCache: temporaryCache()) { citekey in
            try await Task.sleep(for: .seconds(1))
            return self.makeRecord(citekey: citekey)
        }

        let load = Task { await store.load(citekey: "cancelled") }
        try await Task.sleep(for: .milliseconds(10))
        load.cancel()
        await load.value

        XCTAssertNil(store.loadedCitekey)
        XCTAssertNil(store.record)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.error)
    }

    @MainActor
    func testCachedRecordDisplaysSynchronouslyAndRefreshesWithoutBlocking() async throws {
        let cache = temporaryCache()
        let cached = makeRecord(citekey: "cached")
        try cache.save([
            cached.citekey: .init(record: cached, lastAccessedAt: Date())
        ])
        let refreshed = makeRecord(citekey: "cached", title: "refreshed")
        let store = LibraryDetailStore(recordCache: cache) { _ in
            try await Task.sleep(for: .milliseconds(20))
            return refreshed
        }

        XCTAssertEqual(store.displayedRecord(for: "cached"), cached)

        let load = Task { await store.load(citekey: "cached") }
        await Task.yield()
        XCTAssertEqual(store.record, cached)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.isRefreshing)

        await load.value
        XCTAssertEqual(store.record, refreshed)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.error)
    }

    @MainActor
    func testCachedRecordRemainsVisibleWhenRefreshFails() async throws {
        let cache = temporaryCache()
        let cached = makeRecord(citekey: "cached")
        try cache.save([
            cached.citekey: .init(record: cached, lastAccessedAt: Date())
        ])
        let store = LibraryDetailStore(recordCache: cache) { _ in
            throw URLError(.notConnectedToInternet)
        }

        await store.load(citekey: "cached")

        XCTAssertEqual(store.record, cached)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.error)
    }

    @MainActor
    func testRefreshReplacesAnAlreadyLoadedRecord() async throws {
        var title = "before"
        let store = LibraryDetailStore(recordCache: temporaryCache()) { citekey in
            self.makeRecord(citekey: citekey, title: title)
        }
        await store.load(citekey: "Namias1966Nature")
        title = "after"

        await store.load(citekey: "Namias1966Nature")
        XCTAssertEqual(store.record?.title, "before")

        await store.refresh(citekey: "Namias1966Nature")
        XCTAssertEqual(store.record?.title, "after")
    }

    private func temporaryCache() -> LibraryRecordCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return LibraryRecordCache(
            url: directory.appendingPathComponent("records.json")
        )
    }

    private func makeRecord(citekey: String, title: String? = nil) -> LibraryRecord {
        LibraryRecord(
            citekey: citekey,
            type: "journal-article",
            title: title ?? citekey,
            year: 2026,
            doi: nil,
            arxiv: nil,
            isbn: nil,
            pmid: nil,
            pmcid: nil,
            journal: nil,
            volume: nil,
            issue: nil,
            pages: nil,
            publisher: nil,
            url: nil,
            abstract: nil,
            keywords: [],
            authors: [],
            attachments: [],
            addedAt: nil,
            modifiedAt: nil,
            read: false,
            notes: nil
        )
    }
}
