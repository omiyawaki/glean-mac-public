import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class BacklogStore {
    var entries: [BacklogEntry] = []
    var count: Int = 0
    var isLoading: Bool = false
    var lastError: String? = nil
    var hasLoadedOnce: Bool = false
    var lastRefreshedAt: Date? = nil

    private let endpoint = URL(string: "http://backend.example.com:8765/api/backlog")!
    private let minSpinnerDuration: Duration = .milliseconds(700)

    func load() async {
        isLoading = true
        let started = ContinuousClock.now

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastError = "HTTP \(code)"
                await holdSpinner(since: started)
                isLoading = false
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(BacklogResponse.self, from: data)
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

        await holdSpinner(since: started)
        isLoading = false
    }

    /// Ensure the spinner is visible long enough to register as feedback,
    /// even when the underlying operation finishes faster than the eye can
    /// perceive. Apple-precedented: native refresh affordances always show
    /// at least one perceivable cycle of the indicator.
    private func holdSpinner(since started: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - started
        if elapsed < minSpinnerDuration {
            try? await Task.sleep(for: minSpinnerDuration - elapsed)
        }
    }
}
