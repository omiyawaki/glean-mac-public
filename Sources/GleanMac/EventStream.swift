import Foundation
import Observation

/// Long-lived Server-Sent Events consumer. Connects to the backend's `/events`
/// endpoint, listens for `state-changed` events, and invokes `onEvent`
/// (typically a silent store reload). Auto-reconnects with exponential
/// backoff if the stream drops — server restart, network blip, sleep
/// resume.
@MainActor
@Observable
final class EventStream {
    var isConnected: Bool = false

    private let url: URL
    private let onEvent: (String) async -> Void
    private var task: Task<Void, Never>?

    init(url: URL, onEvent: @escaping (String) async -> Void) {
        self.url = url
        self.onEvent = onEvent
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isConnected = false
    }

    private func runLoop() async {
        var backoff: Duration = .seconds(1)
        let maxBackoff: Duration = .seconds(30)
        while !Task.isCancelled {
            do {
                try await connect()
                backoff = .seconds(1)
            } catch is CancellationError {
                return
            } catch {
                isConnected = false
                if Task.isCancelled { return }
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, maxBackoff)
            }
        }
    }

    private func connect() async throws {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Long-lived stream — disable URLSession's per-request timeout.
        request.timeoutInterval = .infinity

        let (stream, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        isConnected = true

        for try await line in stream.lines {
            if Task.isCancelled { break }
            // SSE protocol: lines starting with "event: <name>" mark
            // each named event; comments (":keepalive") and empty
            // separators are ignored. The "ready" hello from the
            // server is forwarded too — the dispatcher decides what to
            // do with it (typically nothing, since .task on the views
            // already runs an initial fetch).
            let prefix = "event: "
            if line.hasPrefix(prefix) {
                let name = String(line.dropFirst(prefix.count))
                await onEvent(name)
            }
        }
    }
}
