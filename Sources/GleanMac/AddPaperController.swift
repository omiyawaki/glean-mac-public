import Foundation
import Observation

@MainActor
@Observable
final class AddPaperController {
    var isPresented = false
    var input = ""
    var errorMessage: String?
    var isSubmitting = false

    var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        !trimmedInput.isEmpty && !isSubmitting
    }

    func present() {
        errorMessage = nil
        isPresented = true
    }

    func submit(
        offlineCoordinator: OfflineIntakeCoordinator,
        syncPendingOperations: () async -> Void
    ) async {
        guard !isSubmitting else { return }

        let candidate = trimmedInput
        guard !candidate.isEmpty else {
            errorMessage = "Enter a DOI."
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            try await offlineCoordinator.queueAddPaper(input: candidate)
            input = ""
            isPresented = false
            isSubmitting = false
            await syncPendingOperations()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }
}
