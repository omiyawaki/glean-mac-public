import Foundation
import Observation
import SwiftUI

/// Loads and exposes the proposed author additions — first-authors of
/// papers the user has saved enough times to suggest following them
/// outright. Identical fetch/spinner mechanics as BacklogStore; action
/// POSTs (Follow, Dismiss) live in IntakeActions.
@MainActor
@Observable
final class AuthorStore {
    var entries: [AuthorProposal] = []
    var count: Int = 0
    var isLoading: Bool = false
    var lastError: String? = nil
    var hasLoadedOnce: Bool = false
    var lastRefreshedAt: Date? = nil

    private let endpoint = URL(string: "http://backend.example.com:8765/api/author-proposals")!
    private let minSpinnerDuration: Duration = .milliseconds(700)

    func load(silent: Bool = false) async {
        let showSpinner = !silent || !hasLoadedOnce
        if showSpinner { isLoading = true }
        let started = ContinuousClock.now

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastError = "HTTP \(code)"
                if showSpinner {
                    await holdSpinner(since: started)
                    isLoading = false
                }
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(AuthorProposalsResponse.self, from: data)
            withAnimation(.smooth) {
                entries = payload.entries
                count = payload.count
                lastError = nil
                hasLoadedOnce = true
                lastRefreshedAt = Date()
            }
        } catch {
            lastError = error.localizedDescription
        }

        if showSpinner {
            await holdSpinner(since: started)
            isLoading = false
        }
    }

    private func holdSpinner(since started: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - started
        if elapsed < minSpinnerDuration {
            try? await Task.sleep(for: minSpinnerDuration - elapsed)
        }
    }
}
