import Foundation

/// Thin wrappers around the four intake-mutation endpoints. Each posts
/// application/x-www-form-urlencoded and returns once the server has
/// committed the change.
///
/// Background refreshes for all four lists (backlog, review, author
/// proposals, library) are driven by the SSE "intake-changed" /
/// "library-changed" events. For the two transient decision lists
/// (Maybe Review and Author Proposals) the Mac app additionally performs
/// a targeted post-mutation load immediately after a successful
/// review/add|skip or author/follow|dismiss so the acting user sees
/// final state with minimal latency (the auto-pruning in IntakeStore
/// then cleans up the optimistic guard). The event path still keeps
/// other clients and background tabs in sync.
enum IntakeActions {
    private static let baseURL = URL(string: "http://backend.example.com:8765")!
    private static let defaultPostTimeout: TimeInterval = 30
    private static let reviewAddTimeout: TimeInterval = 660

    enum ActionError: Error, LocalizedError {
        case http(Int, String)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .http(let code, let detail):
                if let message = Self.serverMessage(from: detail) {
                    return "Server returned HTTP \(code): \(message)"
                }
                return "Server returned HTTP \(code)"
            case .server(let message):
                return message
            }
        }

        static func serverMessage(from detail: String) -> String? {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let data = trimmed.data(using: .utf8),
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return message(from: payload)
            }
            return trimmed
        }

        static func message(from payload: [String: Any]) -> String? {
            for key in ["detail", "error"] {
                if let value = payload[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }
    }

    static func submit(_ operation: PendingOperation) async throws -> PendingOperationSyncResult {
        do {
            switch operation.kind {
            case .reviewAdd(let doi):
                try await reviewAdd(doi: doi, operationID: operation.id)
            case .reviewSkip(let doi):
                try await reviewSkip(doi: doi, operationID: operation.id)
            case .authorFollow(let author):
                try await authorFollow(author: author, operationID: operation.id)
            case .authorDismiss(let author):
                try await authorDismiss(author: author, operationID: operation.id)
            case .attachPDF(let stagedFilePath, let citekey):
                try await attach(file: URL(fileURLWithPath: stagedFilePath),
                                 citekey: citekey,
                                 operationID: operation.id)
            case .addPaper(let input, let stagedPDFPath):
                let trimmedInput = input.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !trimmedInput.isEmpty {
                    try await reviewAdd(doi: trimmedInput,
                                        operationID: operation.id)
                }
                if let stagedPDFPath {
                    try await attach(file: URL(fileURLWithPath: stagedPDFPath),
                                     citekey: nil,
                                     operationID: operation.id)
                }
            }
            return .synced
        } catch ActionError.http(409, let detail) {
            return .needsReview(ActionError.serverMessage(from: detail) ?? "Needs review")
        }
    }

    static func reviewAdd(doi: String, operationID: UUID? = nil) async throws {
        try await post(path: "/api/review/add",
                       form: ["doi": doi],
                       timeoutInterval: reviewAddTimeout,
                       operationID: operationID)
    }

    static func reviewSkip(doi: String, operationID: UUID? = nil) async throws {
        try await post(path: "/api/review/skip",
                       form: ["doi": doi],
                       operationID: operationID)
    }

    static func authorFollow(author: String, operationID: UUID? = nil) async throws {
        try await post(path: "/api/author/follow",
                       form: ["author": author],
                       operationID: operationID)
    }

    static func authorDismiss(author: String, operationID: UUID? = nil) async throws {
        try await post(path: "/api/author/dismiss",
                       form: ["author": author],
                       operationID: operationID)
    }

    /// Multipart upload of a local PDF to home's /attach endpoint. The
    /// server runs a magic-byte check, extracts a DOI from the first
    /// pages, matches against the backlog, and on a hit attaches the
    /// PDF via `glean attach --move` (which also removes the entry
    /// from pdf_backlog.json — picked up by the SSE watcher).
    ///
    /// `citekey` is optional but should be supplied whenever the caller
    /// already knows which backlog entry the download is for. The
    /// backend then bypasses DOI extraction entirely and force-attaches to
    /// that citekey. This is the only
    /// way to land a PDF whose body doesn't print its own DOI — Physics
    /// Today's PT.3.NNNN papers are the canonical example; the
    /// downloaded PDF only contains DOIs of cited works.
    static func attach(file url: URL,
                       citekey: String? = nil,
                       operationID: UUID? = nil) async throws {
        let fileData = try Data(contentsOf: url)
        let boundary = UUID().uuidString

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        if let citekey, !citekey.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"citekey\"\r\n\r\n".data(using: .utf8)!)
            body.append(citekey.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appendingPathComponent("/attach"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        if let operationID {
            request.setValue(operationID.uuidString,
                             forHTTPHeaderField: "X-Glean-Operation-ID")
        }
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
            throw ActionError.server(
                ActionError.message(from: payload) ?? "Upload failed"
            )
        }
    }

    private static func post(path: String,
                             form: [String: String],
                             timeoutInterval: TimeInterval = defaultPostTimeout,
                             operationID: UUID? = nil) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        if let operationID {
            request.setValue(operationID.uuidString,
                             forHTTPHeaderField: "X-Glean-Operation-ID")
        }
        request.timeoutInterval = timeoutInterval
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
            throw ActionError.server(
                ActionError.message(from: payload) ?? "Action failed"
            )
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
