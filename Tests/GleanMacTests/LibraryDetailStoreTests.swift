import XCTest
@testable import GleanMac

final class LibraryDetailStoreTests: XCTestCase {
    @MainActor
    func testNewestSelectionWinsWhenAnEarlierLoadFinishesLater() async throws {
        let store = LibraryDetailStore { citekey in
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
        let store = LibraryDetailStore { citekey in
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

    private func makeRecord(citekey: String) -> LibraryRecord {
        LibraryRecord(
            citekey: citekey,
            type: "journal-article",
            title: citekey,
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
