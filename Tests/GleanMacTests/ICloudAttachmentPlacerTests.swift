import XCTest
@testable import GleanMac

final class ICloudAttachmentPlacerTests: XCTestCase {
    func testPlaceCopiesIntoICloudThenCommitsAndReleases() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staged = root.appendingPathComponent("staged.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("%PDF-1.7\n".utf8).write(to: staged)
        let relative = "attachments/NAMIAS (1966) Drought.pdf"
        var committed: String?
        var released = false
        let placer = ICloudAttachmentPlacer(
            plan: { _ in relative },
            commit: { _, path in committed = path },
            release: { _ in released = true },
            libraryRoot: root
        )

        let destination = try await placer.place(stagedPDF: staged, citekey: "Namias1966Nature")

        XCTAssertEqual(destination.path, root.appendingPathComponent(relative).path)
        XCTAssertEqual(try Data(contentsOf: destination), Data("%PDF-1.7\n".utf8))
        XCTAssertEqual(committed, relative)
        XCTAssertTrue(released)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }

    func testPlaceLeavesTheStagedFileWhenCommitFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staged = root.appendingPathComponent("staged.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("%PDF-1.7\n".utf8).write(to: staged)
        let placer = ICloudAttachmentPlacer(
            plan: { _ in "attachments/Paper.pdf" },
            commit: { _, _ in throw LibraryAttachmentError.server("down") },
            release: { _ in XCTFail("release should wait for commit") },
            libraryRoot: root
        )

        do {
            _ = try await placer.place(stagedPDF: staged, citekey: "Namias1966Nature")
            XCTFail("expected commit to fail")
        } catch LibraryAttachmentError.server {
            XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        }
    }

    func testMaterializerPullsAServerPDFIntoTheICloudPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let relative = "attachments/NAMIAS (1966) Drought.pdf"
        var released = false
        let materializer = LibraryPDFMaterializer(
            libraryRoot: root,
            download: { _ in Data("%PDF-1.7\nserver".utf8) },
            release: { _ in released = true },
            startICloudDownload: { _ in }
        )
        let record = LibraryRecord(
            citekey: "Namias1966Nature",
            type: "journal-article",
            title: "Drought",
            year: 1966,
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
            attachments: [LibraryAttachment(path: relative, kind: "main")],
            addedAt: nil,
            modifiedAt: nil,
            read: false,
            notes: nil
        )

        let availability = await materializer.prepare(record: record)

        guard case .ready(let url) = availability else {
            return XCTFail("expected a ready PDF, got \(availability)")
        }
        XCTAssertEqual(try Data(contentsOf: url), Data("%PDF-1.7\nserver".utf8))
        XCTAssertTrue(released)
    }
}
