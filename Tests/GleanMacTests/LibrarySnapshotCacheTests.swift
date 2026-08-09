import XCTest
@testable import GleanMac

final class LibrarySnapshotCacheTests: XCTestCase {
    func testSaveThenLoadRoundTripsLibraryResponse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = LibrarySnapshotCache(
            url: directory.appendingPathComponent("library.json")
        )
        let response = LibraryResponse(count: 1, entries: [
            LibraryEntry(
                citekey: "Abdi2026Hrrrcast",
                title: "HRRRCast",
                year: 2026,
                publishedAt: "2026-05-03",
                doi: "10.1175/test",
                authors: [LibraryAuthor(family: "Abdi", given: "Daniel")]
            )
        ])

        try await cache.save(response)
        let loaded = try await cache.load()

        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.entries.first?.citekey, "Abdi2026Hrrrcast")
        XCTAssertEqual(loaded?.entries.first?.publishedAt, "2026-05-03")
        XCTAssertEqual(loaded?.entries.first?.authors.first?.family, "Abdi")
    }

    func testLoadMissingSnapshotReturnsNil() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")
        let cache = LibrarySnapshotCache(url: url)

        let loaded = try await cache.load()

        XCTAssertNil(loaded)
    }

    func testLoadCorruptSnapshotThrows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("library.json")
        try Data("not json".utf8).write(to: url)
        let cache = LibrarySnapshotCache(url: url)

        do {
            _ = try await cache.load()
            XCTFail("Expected corrupt snapshot load to throw")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }
}
