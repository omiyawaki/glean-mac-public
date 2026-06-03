import XCTest
@testable import GleanMac

@MainActor
final class AddPaperControllerTests: XCTestCase {
    func testSubmitTrimsDOIQueuesAddPaperAndSyncs() async throws {
        let store = PendingOperationStore(url: tempURL())
        let coordinator = OfflineIntakeCoordinator(operationStore: store)
        let controller = AddPaperController()
        var syncCount = 0
        controller.present()
        controller.input = "  10.1000/new-paper  "

        await controller.submit(
            offlineCoordinator: coordinator,
            syncPendingOperations: { syncCount += 1 }
        )

        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(controller.input, "")
        XCTAssertNil(controller.errorMessage)
        XCTAssertFalse(controller.isSubmitting)
        XCTAssertEqual(syncCount, 1)
        XCTAssertEqual(
            store.operations.first?.kind,
            .addPaper(input: "10.1000/new-paper", stagedPDFPath: nil)
        )
    }

    func testSubmitDismissesPopoverBeforeAwaitingServerSync() async throws {
        let store = PendingOperationStore(url: tempURL())
        let coordinator = OfflineIntakeCoordinator(operationStore: store)
        let controller = AddPaperController()
        controller.present()
        controller.input = "10.1000/new-paper"
        var stateDuringSync: (isPresented: Bool, input: String, isSubmitting: Bool)?

        await controller.submit(
            offlineCoordinator: coordinator,
            syncPendingOperations: {
                stateDuringSync = (
                    controller.isPresented,
                    controller.input,
                    controller.isSubmitting
                )
            }
        )

        XCTAssertEqual(stateDuringSync?.isPresented, false)
        XCTAssertEqual(stateDuringSync?.input, "")
        XCTAssertEqual(stateDuringSync?.isSubmitting, false)
    }

    func testSubmitRejectsWhitespaceInputWithoutQueueing() async throws {
        let store = PendingOperationStore(url: tempURL())
        let coordinator = OfflineIntakeCoordinator(operationStore: store)
        let controller = AddPaperController()
        var syncCount = 0
        controller.present()
        controller.input = "   "

        await controller.submit(
            offlineCoordinator: coordinator,
            syncPendingOperations: { syncCount += 1 }
        )

        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.errorMessage, "Enter a DOI.")
        XCTAssertFalse(controller.isSubmitting)
        XCTAssertEqual(syncCount, 0)
        XCTAssertTrue(store.operations.isEmpty)
    }

    func testPresentClearsStaleErrorAndShowsPopover() {
        let controller = AddPaperController()
        controller.errorMessage = "Previous failure"

        controller.present()

        XCTAssertTrue(controller.isPresented)
        XCTAssertNil(controller.errorMessage)
    }

    func testSubmitWhileAlreadySubmittingDoesNotQueueDuplicate() async throws {
        let store = PendingOperationStore(url: tempURL())
        let coordinator = OfflineIntakeCoordinator(operationStore: store)
        let controller = AddPaperController()
        var syncCount = 0
        controller.present()
        controller.input = "10.1000/new-paper"
        controller.isSubmitting = true

        await controller.submit(
            offlineCoordinator: coordinator,
            syncPendingOperations: { syncCount += 1 }
        )

        XCTAssertTrue(store.operations.isEmpty)
        XCTAssertEqual(syncCount, 0)
        XCTAssertTrue(controller.isSubmitting)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("operations.json")
    }
}
