#if DEBUG

import Foundation
import Network
import os

private let log = Logger(subsystem: "com.miyawaki.glean-mac", category: "introspection")

/// Pull Content-Length out of HTTP/1.1 request headers. Returns 0 when missing
/// or unparseable, which is the desired behavior for GET requests without a body.
private func parseContentLength(headerData: Data) -> Int {
    guard let s = String(data: headerData, encoding: .utf8) else { return 0 }
    for line in s.components(separatedBy: "\r\n") {
        guard let colon = line.firstIndex(of: ":") else { continue }
        let name = line[..<colon].lowercased()
        if name == "content-length" {
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return Int(value) ?? 0
        }
    }
    return 0
}

/// Localhost-only HTTP server that exposes the introspection registry as JSON.
/// Started in DEBUG builds from `GleanMacApp`. Endpoints:
///
///   GET  /                  liveness, returns server info + action ids
///   GET  /tree              registered elements: id, kind, label, value, enabled
///   GET  /focus             { focusedId: "..." | null }
///   GET  /state             registered state providers, JSON dictionary
///   POST /action/{id}       invoke a registered action; { ok: true|false }
///
/// The server binds 127.0.0.1 only; ATS allows insecure HTTP on localhost via
/// the existing exception in Info.plist. No auth, no TLS. DEBUG builds only.
@MainActor
final class IntrospectionServer {
    static let shared = IntrospectionServer()
    private init() {}

    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    func start(port: UInt16 = 17317) {
        guard listener == nil else { return }
        do {
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: nwPort)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    log.info("introspection ready on 127.0.0.1:\(port, privacy: .public)")
                case .failed(let err):
                    log.error("introspection listener failed: \(err.localizedDescription, privacy: .public)")
                default:
                    break
                }
            }
            l.start(queue: .main)
            listener = l
            self.port = port
        } catch {
            log.error("introspection start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        readRequest(connection, accumulated: Data())
    }

    private func readRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if let error = error {
                log.debug("recv error: \(error.localizedDescription, privacy: .public)")
                connection.cancel(); return
            }
            var buf = accumulated
            if let data = data { buf.append(data) }
            if let headerEnd = buf.range(of: Data([0x0d, 0x0a, 0x0d, 0x0a])) {
                let headerData = buf.subdata(in: 0..<headerEnd.lowerBound)
                let bodyStart = headerEnd.upperBound
                let contentLength = parseContentLength(headerData: headerData)
                let bodyAvailable = buf.count - bodyStart
                if bodyAvailable >= contentLength {
                    let bodyData = contentLength > 0
                        ? buf.subdata(in: bodyStart..<(bodyStart + contentLength))
                        : Data()
                    Task { @MainActor in
                        let response = await self.respond(headerData: headerData, bodyData: bodyData)
                        connection.send(content: response, completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    }
                    return
                }
            }
            if isComplete {
                connection.cancel(); return
            }
            // Need more data; keep reading.
            Task { @MainActor in self.readRequest(connection, accumulated: buf) }
        }
    }

    private func respond(headerData: Data, bodyData: Data) async -> Data {
        guard let request = String(data: headerData, encoding: .utf8),
              let firstLine = request.split(separator: "\r\n").first else {
            return httpResponse(status: 400, body: jsonData(["error": "bad request"]))
        }
        let parts = firstLine.split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            return httpResponse(status: 400, body: jsonData(["error": "bad request line"]))
        }
        let method = parts[0]
        let path = parts[1]

        var payload: [String: Any]? = nil
        if !bodyData.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            payload = json
        }
        return await route(method: method, path: path, payload: payload)
    }

    // MARK: - Routing

    private func route(method: String, path: String, payload: [String: Any]?) async -> Data {
        let registry = IntrospectionRegistry.shared
        switch (method, path) {
        case ("GET", "/"):
            let info: [String: AnyEncodable] = [
                "service": AnyEncodable("glean-introspection"),
                "port": AnyEncodable(port),
                "actions": AnyEncodable(registry.actionIDs())
            ]
            return httpResponse(status: 200, body: jsonData(info))

        case ("GET", "/tree"):
            return httpResponse(status: 200, body: jsonData(registry.tree()))

        case ("GET", "/focus"):
            return httpResponse(status: 200, body: jsonData(["focusedId": registry.focusedId]))

        case ("GET", "/state"):
            return httpResponse(status: 200, body: jsonData(registry.stateSnapshot()))

        case ("POST", let p) where p.hasPrefix("/action/"):
            let id = String(p.dropFirst("/action/".count))
            let ran = await registry.runAction(id: id, payload: payload)
            let status = ran ? 200 : 404
            let body: [String: AnyEncodable] = [
                "ok": AnyEncodable(ran),
                "id": AnyEncodable(id)
            ]
            return httpResponse(status: status, body: jsonData(body))

        default:
            let body: [String: AnyEncodable] = [
                "error": AnyEncodable("not found"),
                "path": AnyEncodable(path)
            ]
            return httpResponse(status: 404, body: jsonData(body))
        }
    }

    // MARK: - HTTP helpers

    private func jsonData<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    private func httpResponse(status: Int, body: Data) -> Data {
        let reason = reasonPhrase(status)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    private func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        default: return "OK"
        }
    }
}

#endif
