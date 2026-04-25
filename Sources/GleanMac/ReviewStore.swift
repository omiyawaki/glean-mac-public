import Foundation
import Observation
import SwiftUI

/// Loads and exposes the worker's "maybe" review queue — papers the
/// relevance filter wasn't confident enough to auto-accept or auto-reject.
/// Identical fetch/spinner mechanics as BacklogStore; kept separate for
/// clarity. Action POSTs (Add, Skip) live in IntakeActions and trigger a
/// silent reload via the SSE push when they mutate review_queue.md.
@MainActor
@Observable
final class ReviewStore {
    var entries: [ReviewEntry] = []
    var count: Int = 0
    var isLoading: Bool = false
    var lastError: String? = nil
    var hasLoadedOnce: Bool = false
    var lastRefreshedAt: Date? = nil

    private let endpoint = URL(string: "http://backend.example.com:8765/api/review-queue")!
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
            let payload = try decoder.decode(ReviewResponse.self, from: data)
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
