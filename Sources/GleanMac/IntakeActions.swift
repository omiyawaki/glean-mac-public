import Foundation

/// Thin wrappers around the four intake-mutation endpoints. Each posts
/// application/x-www-form-urlencoded and returns once the server has
/// committed the change. The corresponding store will refresh on the
/// next /events tick — no manual reload needed at the call site.
enum IntakeActions {
    private static let baseURL = URL(string: "http://backend.example.com:8765")!

    enum ActionError: Error, LocalizedError {
        case http(Int, String)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .http(let code, _): "Server returned HTTP \(code)"
            case .server(let message): message
            }
        }
    }

    static func reviewAdd(doi: String) async throws {
        try await post(path: "/api/review/add", form: ["doi": doi])
    }

    static func reviewSkip(doi: String) async throws {
        try await post(path: "/api/review/skip", form: ["doi": doi])
    }

    static func authorFollow(author: String) async throws {
        try await post(path: "/api/author/follow", form: ["author": author])
    }

    static func authorDismiss(author: String) async throws {
        try await post(path: "/api/author/dismiss", form: ["author": author])
    }

    /// Multipart upload of a local PDF to the backend's /attach endpoint. The
    /// server runs a magic-byte check, extracts a DOI from the first
    /// pages, matches against the backlog, and on a hit attaches the
    /// PDF via `glean attach --move` (which also removes the entry
    /// from pdf_backlog.json — picked up by the SSE watcher).
    static func attach(file url: URL) async throws {
        let fileData = try Data(contentsOf: url)
        let boundary = UUID().uuidString

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appendingPathComponent("/attach"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ActionError.server("Invalid response")
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw ActionError.http(http.statusCode, detail)
        }
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ok = payload["ok"] as? Bool, !ok {
            let detail = (payload["error"] as? String)
                ?? (payload["detail"] as? String)
                ?? "Upload failed"
            throw ActionError.server(detail)
        }
    }

    private static func post(path: String, form: [String: String]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = encode(form: form).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ActionError.server("Invalid response")
        }
        guard http.statusCode == 200 else {
            throw ActionError.http(http.statusCode,
                                   String(data: data, encoding: .utf8) ?? "")
        }
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ok = payload["ok"] as? Bool, !ok {
            let detail = (payload["error"] as? String)
                ?? (payload["detail"] as? String)
                ?? "Action failed"
            throw ActionError.server(detail)
        }
    }

    private static func encode(form: [String: String]) -> String {
        form.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
    }
}
