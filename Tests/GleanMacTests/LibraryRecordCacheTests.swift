import XCTest
@testable import GleanMac

final class LibraryRecordCacheTests: XCTestCase {
    func testSaveThenLoadRoundTripsRecords() throws {
        let cache = makeCache(maximumRecordCount: 4)
        let first = makeRecord(citekey: "first")
        let second = makeRecord(citekey: "second")

        try cache.save([
            first.citekey: .init(record: first, lastAccessedAt: Date(timeIntervalSince1970: 1)),
            second.citekey: .init(record: second, lastAccessedAt: Date(timeIntervalSince1970: 2))
        ])

        let loaded = try cache.load()
        XCTAssertEqual(loaded["first"]?.record, first)
        XCTAssertEqual(loaded["second"]?.record, second)
    }

    func testCacheRetainsOnlyMostRecentlyAccessedRecords() throws {
        let cache = makeCache(maximumRecordCount: 2)
        let oldest = makeRecord(citekey: "oldest")
        let middle = makeRecord(citekey: "middle")
        let newest = makeRecord(citekey: "newest")

        try cache.save([
            oldest.citekey: .init(record: oldest, lastAccessedAt: Date(timeIntervalSince1970: 1)),
            middle.citekey: .init(record: middle, lastAccessedAt: Date(timeIntervalSince1970: 2)),
            newest.citekey: .init(record: newest, lastAccessedAt: Date(timeIntervalSince1970: 3))
        ])

        let loaded = try cache.load()
        XCTAssertEqual(Set(loaded.keys), ["middle", "newest"])
    }

    private func makeCache(maximumRecordCount: Int) -> LibraryRecordCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return LibraryRecordCache(
            url: directory.appendingPathComponent("records.json"),
            maximumRecordCount: maximumRecordCount
        )
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
