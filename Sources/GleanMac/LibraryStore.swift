import Foundation
import Observation
import SwiftUI

/// Loads the full library list from glean's HTTP API on a different
/// port than the intake server (8766 vs 8765). Same fetch / spinner
/// mechanics as the intake stores. The list is large (thousands of
/// records) but a single fetch + decode finishes well under a second
/// over tailnet, and SwiftUI's List virtualizes the rendering.
@MainActor
@Observable
final class LibraryStore {
    var entries: [LibraryEntry] = []
    var count: Int = 0
    var isLoading: Bool = false
    var lastError: String? = nil
    var hasLoadedOnce: Bool = false
    var lastRefreshedAt: Date? = nil

    private let endpoint = URL(string: "http://backend.example.com:8766/api/papers")!
    private let minSpinnerDuration: Duration = .milliseconds(700)

    func load(silent: Bool = false) async {
        let showSpinner = !silent || !hasLoadedOnce
        if showSpinner { isLoading = true }
        let started = ContinuousClock.now

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 15
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
            let payload = try decoder.decode(LibraryResponse.self, from: data)
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
