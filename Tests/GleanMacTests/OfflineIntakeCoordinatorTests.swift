import XCTest
@testable import GleanMac

@MainActor
final class OfflineIntakeCoordinatorTests: XCTestCase {
    func testQueueAttachStagesPDFAndRecordsOperation() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("%PDF-1.7\nattach".utf8).write(to: source)
        let store = PendingOperationStore(url: tempURL())
        let stager = PendingPDFStager(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let coordinator = OfflineIntakeCoordinator(
            operationStore: store,
            pdfStager: stager
        )

        let operation = try await coordinator.queueAttachPDF(source,
                                                             citekey: "Abdi2026Hrrrcast")

        XCTAssertEqual(store.operations.count, 1)
        XCTAssertEqual(store.operations.first?.id, operation.id)
        if case .attachPDF(let stagedFilePath, let citekey) = operation.kind {
            XCTAssertEqual(citekey, "Abdi2026Hrrrcast")
            XCTAssertTrue(FileManager.default.fileExists(atPath: stagedFilePath))
            XCTAssertNotEqual(stagedFilePath, source.path)
        } else {
            XCTFail("Expected attachPDF operation")
        }
    }

    func testQueueDeletePaperRecordsCitekeyAndDOI() async throws {
        let store = PendingOperationStore(url: tempURL())
        let coordinator = OfflineIntakeCoordinator(operationStore: store)

        let operation = try await coordinator.queueDeletePaper(
            citekey: " Miyawaki2024Attention ",
            doi: " 10.1175/JCLI-D-23-0456.1 ",
            title: " Attention and convection "
        )

        XCTAssertEqual(
            operation.kind,
            .deletePaper(
                citekey: "Miyawaki2024Attention",
                doi: "10.1175/JCLI-D-23-0456.1",
                title: "Attention and convection"
            )
        )
        XCTAssertEqual(store.pendingOperations.map(\.id), [operation.id])
    }

    func testQueueReviewAddRecordsOperationWithoutServerCall() async throws {
        let store = PendingOperationStore(url: tempURL())
        let coordinator = OfflineIntakeCoordinator(operationStore: store)

        let operation = try await coordinator.queueReviewAdd(doi: "10.1000/add")

        XCTAssertEqual(operation.kind, .reviewAdd(doi: "10.1000/add"))
        XCTAssertEqual(store.pendingOperations.map(\.id), [operation.id])
    }

    func testQueueAddPaperRecordsInputAndOptionalPDF() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("%PDF-1.7\nadd".utf8).write(to: source)
        let store = PendingOperationStore(url: tempURL())
        let stager = PendingPDFStager(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let coordinator = OfflineIntakeCoordinator(
            operationStore: store,
            pdfStager: stager
        )

        let operation = try await coordinator.queueAddPaper(input: "10.1000/new",
                                                            pdf: source)

        if case .addPaper(let input, let stagedPDFPath) = operation.kind {
            XCTAssertEqual(input, "10.1000/new")
            XCTAssertNotNil(stagedPDFPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stagedPDFPath!))
        } else {
            XCTFail("Expected addPaper operation")
        }
    }

    func testQueueAddPaperRecordsDOIOnlyInput() async throws {
        let store = PendingOperationStore(url: tempURL())
        let coordinator = OfflineIntakeCoordinator(operationStore: store)

        let operation = try await coordinator.queueAddPaper(input: "10.1000/new")

        XCTAssertEqual(operation.kind, .addPaper(input: "10.1000/new",
                                                stagedPDFPath: nil))
    }

    func testQueueAddPaperRecordsURLOnlyInput() async throws {
        let store = PendingOperationStore(url: tempURL())
        let coordinator = OfflineIntakeCoordinator(operationStore: store)

        let operation = try await coordinator.queueAddPaper(
            input: "https://example.org/paper"
        )

        XCTAssertEqual(operation.kind, .addPaper(input: "https://example.org/paper",
                                                stagedPDFPath: nil))
    }

    func testQueueAddPaperWithPDFOnlyUsesExtractedDOIAsInput() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("%PDF-1.7\n10.1175/JAS-D-25-0123.1\n".utf8).write(to: source)
        let store = PendingOperationStore(url: tempURL())
        let stager = PendingPDFStager(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let coordinator = OfflineIntakeCoordinator(
            operationStore: store,
            pdfStager: stager,
            signalExtractor: .default
        )

        let operation = try await coordinator.queueAddPaper(input: "", pdf: source)

        if case .addPaper(let input, let stagedPDFPath) = operation.kind {
            XCTAssertEqual(input, "10.1175/JAS-D-25-0123.1")
            XCTAssertNotNil(stagedPDFPath)
        } else {
            XCTFail("Expected addPaper operation")
        }
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("operations.json")
    }
}
