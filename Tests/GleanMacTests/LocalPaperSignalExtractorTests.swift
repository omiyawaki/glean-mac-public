import XCTest
@testable import GleanMac

final class LocalPaperSignalExtractorTests: XCTestCase {
    func testExtractsDOICandidatesFromPDFBytes() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("%PDF-1.7\nBody text DOI: 10.1175/JAS-D-25-0123.1.\n".utf8)
            .write(to: url)

        let candidates = try await LocalPaperSignalExtractor.default
            .doiCandidates(in: url)

        XCTAssertEqual(candidates, ["10.1175/JAS-D-25-0123.1"])
    }

    func testDeduplicatesDOICandidatesCaseInsensitively() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("10.1000/Test 10.1000/test".utf8).write(to: url)

        let candidates = try await LocalPaperSignalExtractor.default
            .doiCandidates(in: url)

        XCTAssertEqual(candidates, ["10.1000/Test"])
    }
}
