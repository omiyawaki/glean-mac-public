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
        XCTAssertNil(response.entries[1].year)
    }

    func testReadMissingIndexReturnsNil() async throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let reader = LocalLibraryIndexReader(databaseURL: db)

        let response = try await reader.load()

        XCTAssertNil(response)
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
