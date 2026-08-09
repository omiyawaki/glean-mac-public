import XCTest
@testable import GleanMac

final class LocalLibraryIndexReaderTests: XCTestCase {
    func testReadBuildsLibraryResponseFromSQLiteIndex() async throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        try runSQLite(db: db, sql: """
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
          VALUES ('Later2026Paper', 'Later paper', 2026, '10.1000/later');
        INSERT INTO records(citekey, title, year, doi)
          VALUES ('UndatedPaper', 'Undated paper', NULL, NULL);
        INSERT INTO authors(citekey, ord, family, given)
          VALUES ('Later2026Paper', 0, 'Later', 'Alice');
        INSERT INTO authors(citekey, ord, family, given)
          VALUES ('Later2026Paper', 1, 'Second', NULL);
        """)
        let reader = LocalLibraryIndexReader(databaseURL: db)

        let maybeResponse = try await reader.load()
        let response = try XCTUnwrap(maybeResponse)

        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.entries.map(\.citekey), ["Later2026Paper", "UndatedPaper"])
        XCTAssertEqual(response.entries[0].authors.map(\.family), ["Later", "Second"])
        XCTAssertEqual(response.entries[0].authors[1].given, "")
        XCTAssertNil(response.entries[0].publishedAt)
        XCTAssertNil(response.entries[0].addedAt)
        XCTAssertNil(response.entries[1].year)
    }

    func testReadOrdersSameYearByPublicationDateThenAddedDate() async throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        try runSQLite(db: db, sql: """
        CREATE TABLE records (
          citekey TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          year INTEGER,
          doi TEXT,
          published_at TEXT,
          added_at TEXT
        );
        CREATE TABLE authors (
          citekey TEXT,
          ord INTEGER,
          family TEXT,
          given TEXT
        );
        INSERT INTO records(citekey, title, year, doi, published_at, added_at)
          VALUES ('Alpha2026Older', 'Older', 2026, NULL, '2026-04-01', '2026-06-01');
        INSERT INTO records(citekey, title, year, doi, published_at, added_at)
          VALUES ('Zulu2026Newer', 'Newer', 2026, NULL, '2026-05-01', '2026-03-01');
        INSERT INTO records(citekey, title, year, doi, published_at, added_at)
          VALUES ('Beta2025Newest', 'Older year', 2025, NULL, '2025-12-01', '2026-07-01');
        """)
        let reader = LocalLibraryIndexReader(databaseURL: db)

        let maybeResponse = try await reader.load()
        let response = try XCTUnwrap(maybeResponse)

        XCTAssertEqual(
            response.entries.map(\.citekey),
            ["Zulu2026Newer", "Alpha2026Older", "Beta2025Newest"]
        )
        XCTAssertEqual(response.entries[0].publishedAt, "2026-05-01")
        XCTAssertEqual(response.entries[0].addedAt, "2026-03-01")
    }

    func testReadMissingIndexReturnsNil() async throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let reader = LocalLibraryIndexReader(databaseURL: db)

        let response = try await reader.load()

        XCTAssertNil(response)
    }

    func testReadDrainsLargeSQLiteOutputWithoutDeadlocking() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let db = directory.appendingPathComponent("index.sqlite")
        FileManager.default.createFile(atPath: db.path, contents: Data())
        let fakeSQLite = directory.appendingPathComponent("sqlite3-fake")
        try """
        #!/bin/sh
        query="$3"
        case "$query" in
          *"FROM records"*)
            printf '['
            i=0
            while [ "$i" -lt 5000 ]; do
              if [ "$i" -gt 0 ]; then printf ','; fi
              printf '{"citekey":"Paper%s","title":"Large output paper %s","year":2026,"doi":"10.1000/%s"}' "$i" "$i" "$i"
              i=$((i + 1))
            done
            printf ']'
            ;;
          *"FROM authors"*)
            printf '[]'
            ;;
          *)
            printf '[]'
            ;;
        esac
        """.write(to: fakeSQLite, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeSQLite.path
        )
        let reader = LocalLibraryIndexReader(databaseURL: db,
                                             sqliteExecutableURL: fakeSQLite)
        let finished = expectation(description: "large sqlite output drained")

        Task {
            do {
                let response = try await reader.load()
                XCTAssertEqual(response?.count, 5000)
            } catch {
                XCTFail("load failed: \(error)")
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 2.0)
    }

    private func runSQLite(db: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [db.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
