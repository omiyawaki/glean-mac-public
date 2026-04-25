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

    private let endpoint = URL(string: "http://backend.example.com:8765/api/backlog")!

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastError = "HTTP \(code)"
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
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
