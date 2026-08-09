import XCTest
@testable import GleanMac

final class BacklogSnapshotCacheTests: XCTestCase {
    func testSaveThenLoadRoundTripsBacklogResponse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = BacklogSnapshotCache(
            url: directory.appendingPathComponent("backlog.json")
        )
        let response = BacklogResponse(count: 1, entries: [
            BacklogEntry(
                citekey: "Cached2026Paper",
                doi: "10.1000/cached",
                title: "Cached paper",
                addedAt: Date(timeIntervalSince1970: 0),
                lastAttemptAt: nil,
                tried: ["publisher"]
            )
        ])

        try await cache.save(response)
        let loaded = try await cache.load()

        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.entries.first?.citekey, "Cached2026Paper")
        XCTAssertEqual(loaded?.entries.first?.tried, ["publisher"])
    }

    func testLoadMissingSnapshotReturnsNil() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")

        let loaded = try await BacklogSnapshotCache(url: url).load()

        XCTAssertNil(loaded)
    }

    func testLoadCorruptSnapshotThrows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("backlog.json")
        try Data("not json".utf8).write(to: url)

        do {
            _ = try await BacklogSnapshotCache(url: url).load()
            XCTFail("Expected corrupt snapshot load to throw")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }
}
