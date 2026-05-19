import XCTest
@testable import GleanMac

/// Decode tests against literal JSON shapes returned by the live
/// servers. These guard against a server-side payload change silently
/// breaking the client's decode path.
final class ModelDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_: T.Type, from json: String) throws -> T {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - BacklogResponse

    func testBacklogResponseDecodesTopLevelShape() throws {
        let json = """
        {
          "count": 2,
          "entries": [
            {
              "added_at": "2026-04-24T19:47:00Z",
              "citekey": "Hay2025Impact",
              "doi": "10.1002/qj.70012",
              "last_attempt_at": "2026-04-24T19:47:00Z",
              "missing_attachment_paths": ["attachments/missing.pdf"],
              "source": "glean",
              "state": "attachment_file_missing",
              "title": "The impact of Arctic sea-ice loss",
              "tried": []
            },
            {
              "added_at": "2026-04-25T08:00:00Z",
              "citekey": "Doe2025Other",
              "doi": "10.1000/x",
              "last_attempt_at": null,
              "title": "Another paper",
              "tried": ["https://example.com/x"]
            }
          ]
        }
        """
        let payload = try decode(BacklogResponse.self, from: json)
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload.entries.count, 2)
        XCTAssertEqual(payload.entries[0].citekey, "Hay2025Impact")
        XCTAssertEqual(payload.entries[0].doi, "10.1002/qj.70012")
        XCTAssertNotNil(payload.entries[0].lastAttemptAt)
        XCTAssertEqual(payload.entries[0].state, .attachmentFileMissing)
        XCTAssertEqual(payload.entries[0].source, "glean")
        XCTAssertEqual(payload.entries[0].missingAttachmentPaths, ["attachments/missing.pdf"])
        XCTAssertEqual(payload.entries[0].statusText, "Attachment file missing")
        XCTAssertNil(payload.entries[1].lastAttemptAt)
        XCTAssertEqual(payload.entries[1].state, .unknown)
        XCTAssertEqual(payload.entries[1].statusText, "Manual retrieval needed")
        XCTAssertEqual(payload.entries[1].tried, ["https://example.com/x"])
    }

    // MARK: - ReviewResponse

    func testReviewResponseDecodes() throws {
        let json = """
        {
          "count": 1,
          "entries": [
            {
              "doi": "10.1000/x",
              "url": "https://example.com",
              "title": "Some maybe paper",
              "authors": "A. Smith, B. Jones",
              "journal": "Nature",
              "confidence": "moderate",
              "queued_at": "2026-04-25T07:30:00Z",
              "reasoning": "uncertain match for interests"
            }
          ]
        }
        """
        let payload = try decode(ReviewResponse.self, from: json)
        XCTAssertEqual(payload.count, 1)
        let entry = payload.entries[0]
        XCTAssertEqual(entry.doi, "10.1000/x")
        XCTAssertEqual(entry.confidence, "moderate")
        XCTAssertEqual(entry.queuedAt, "2026-04-25T07:30:00Z")
    }

    // MARK: - AuthorProposalsResponse

    func testAuthorProposalsResponseDecodes() throws {
        let json = """
        {
          "count": 1,
          "entries": [
            {
              "author": "Jane Doe",
              "count": 4,
              "samples": [
                {"doi": "10.1000/a", "title": "First"},
                {"doi": "10.1000/b", "title": "Second"}
              ]
            }
          ]
        }
        """
        let payload = try decode(AuthorProposalsResponse.self, from: json)
        XCTAssertEqual(payload.entries[0].author, "Jane Doe")
        XCTAssertEqual(payload.entries[0].count, 4)
        XCTAssertEqual(payload.entries[0].samples.count, 2)
    }

    // MARK: - LibraryResponse

    func testLibraryResponseDecodesWithNullYearAndDOI() throws {
        let json = """
        {
          "count": 2,
          "entries": [
            {
              "citekey": "Abc2024Test",
              "title": "Some paper",
              "year": 2024,
              "doi": "10.1000/x",
              "authors": [{"family": "Doe", "given": "Jane"}]
            },
            {
              "citekey": "NoYear",
              "title": "Undated paper",
              "year": null,
              "doi": null,
              "authors": []
            }
          ]
        }
        """
        let payload = try decode(LibraryResponse.self, from: json)
        XCTAssertEqual(payload.entries.count, 2)
        XCTAssertEqual(payload.entries[0].year, 2024)
        XCTAssertNil(payload.entries[1].year)
        XCTAssertNil(payload.entries[1].doi)
    }

    // MARK: - LibraryRecord (detail endpoint)

    func testLibraryRecordDecodesFullShape() throws {
        let json = """
        {
          "citekey": "Abdi2026Hrrrcast",
          "type": "journal-article",
          "title": "HRRRCast",
          "year": 2026,
          "doi": "10.1175/aies-d-25-0061.1",
          "arxiv": null,
          "isbn": null,
          "pmid": null,
          "pmcid": null,
          "journal": "Artificial Intelligence for the Earth Systems",
          "volume": "5",
          "issue": "2",
          "pages": null,
          "publisher": "American Meteorological Society",
          "url": "https://doi.org/10.1175/aies-d-25-0061.1",
          "abstract": "An emulator paper.",
          "keywords": ["weather", "ml"],
          "authors": [{"family": "Abdi", "given": "Daniel"}],
          "attachments": [{"path": "attachments/Abdi et al (2026).pdf", "kind": "main"}],
          "added_at": "2026-04-22",
          "modified_at": "2026-04-22",
          "read": false,
          "notes": ""
        }
        """
        let record = try decode(LibraryRecord.self, from: json)
        XCTAssertEqual(record.citekey, "Abdi2026Hrrrcast")
        XCTAssertEqual(record.year, 2026)
        XCTAssertEqual(record.journal, "Artificial Intelligence for the Earth Systems")
        XCTAssertEqual(record.attachments.first?.path, "attachments/Abdi et al (2026).pdf")
        XCTAssertEqual(record.attachments.first?.kind, "main")
        XCTAssertEqual(record.keywords, ["weather", "ml"])
        XCTAssertFalse(record.read)
    }

    func testLibraryRecordDecodesWithMissingOptionals() throws {
        // Records freshly added by paper_intake often have only the
        // bare minimum fields populated.
        let json = """
        {
          "citekey": "Min1990Bare",
          "type": null,
          "title": "Bare record",
          "year": null,
          "doi": null,
          "arxiv": null,
          "isbn": null,
          "pmid": null,
          "pmcid": null,
          "journal": null,
          "volume": null,
          "issue": null,
          "pages": null,
          "publisher": null,
          "url": null,
          "abstract": null,
          "keywords": [],
          "authors": [],
          "attachments": [],
          "added_at": null,
          "modified_at": null,
          "read": false,
          "notes": null
        }
        """
        let record = try XCTUnwrap(try? decode(LibraryRecord.self, from: json))
        XCTAssertEqual(record.citekey, "Min1990Bare")
        XCTAssertEqual(record.attachments.count, 0)
        XCTAssertEqual(record.authors.count, 0)
        XCTAssertEqual(record.keywords.count, 0)
    }
}
