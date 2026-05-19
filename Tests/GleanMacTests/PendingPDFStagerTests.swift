import XCTest
@testable import GleanMac

final class PendingPDFStagerTests: XCTestCase {
    func testStageCopiesPDFToDurableDirectory() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("%PDF-1.7\nsample".utf8).write(to: source)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stager = PendingPDFStager(directory: directory)

        let staged = try await stager.stage(source)

        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertEqual(try Data(contentsOf: staged), try Data(contentsOf: source))
        XCTAssertEqual(staged.deletingLastPathComponent(), directory)
        XCTAssertEqual(staged.pathExtension.lowercased(), "pdf")
    }

    func testStageRejectsNonPDFExtension() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("not a pdf".utf8).write(to: source)
        let stager = PendingPDFStager(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )

        do {
            _ = try await stager.stage(source)
            XCTFail("Expected non-PDF file to be rejected")
        } catch PendingPDFStager.StageError.notPDF {
            XCTAssertTrue(true)
        }
    }
}
