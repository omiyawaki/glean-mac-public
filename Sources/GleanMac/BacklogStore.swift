import Foundation
import Observation

@MainActor
@Observable
final class BacklogStore {
    enum LoadState {
        case idle
        case loading
        case loaded(BacklogResponse)
        case failed(String)
    }

    var state: LoadState = .idle

    private let endpoint = URL(string: "http://backend.example.com:8765/api/backlog")!

    func load() async {
        state = .loading
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                state = .failed("HTTP \(code)")
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(BacklogResponse.self, from: data)
            state = .loaded(payload)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
