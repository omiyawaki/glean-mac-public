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
        Self.normalizedPaperInput(input)
    }

    var canSubmit: Bool {
        !trimmedInput.isEmpty && !isSubmitting
    }

    func present() {
        errorMessage = nil
        isPresented = true
    }

    func normalizeInputForEditing() {
        let normalized = Self.normalizedPaperInput(input)
        if normalized != input {
            input = normalized
        }
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

    private static func normalizedPaperInput(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host == "doi.org" || host == "dx.doi.org"
        else {
            return trimmed
        }
        let doi = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return doi.isEmpty ? trimmed : doi
    }
}
