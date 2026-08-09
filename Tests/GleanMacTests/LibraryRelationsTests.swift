import XCTest
@testable import GleanMac

final class LibraryRelationsTests: XCTestCase {
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
}
