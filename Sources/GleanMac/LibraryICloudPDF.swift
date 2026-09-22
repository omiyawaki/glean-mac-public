import Foundation

enum LibraryPDFAvailability: Equatable {
    case noAttachment
    case ready(URL)
    case downloadingFromICloud
    case unavailable
}

enum LibraryAttachmentError: LocalizedError, Equatable {
    case invalidPath(String)
    case server(String)
    case notAPDF

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            "The library returned an attachment path that cannot be stored in iCloud: \(path)"
        case .server(let message):
            message
        case .notAPDF:
            "The downloaded file is not a PDF."
        }
    }
}

struct LibraryAttachmentClient {
    let endpoints: GleanBackendEndpoints
    let session: URLSession

    static let system = LibraryAttachmentClient()

    init(
        endpoints: GleanBackendEndpoints = .home,
        session: URLSession = .shared
    ) {
        self.endpoints = endpoints
        self.session = session
    }

    func plan(citekey: String) async throws -> String {
        let body = try await post(
            endpoints.libraryAttachmentPlanURL(citekey: citekey),
            form: nil
        )
        guard body.ok, let path = body.relativePath, !path.isEmpty else {
            throw LibraryAttachmentError.server(body.error ?? "Could not plan the PDF path")
        }
        return path
    }

    func commit(citekey: String, relativePath: String) async throws {
        let body = try await post(
            endpoints.libraryAttachmentCommitURL(citekey: citekey),
            form: ["relative_path": relativePath]
        )
        guard body.ok else {
            throw LibraryAttachmentError.server(body.error ?? "Could not record the PDF path")
        }
    }

    func release(citekey: String) async throws {
        _ = try await post(
            endpoints.libraryAttachmentReleaseURL(citekey: citekey),
            form: nil
        )
    }

    func pdfData(citekey: String) async throws -> Data {
        let (data, response) = try await session.data(
            from: endpoints.libraryPDFURL(citekey: citekey)
        )
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LibraryAttachmentError.server("The PDF is not on the library server")
        }
        guard data.starts(with: Data("%PDF-".utf8)) else {
            throw LibraryAttachmentError.notAPDF
        }
        return data
    }

    private struct ResponseBody: Decodable {
        let ok: Bool
        let relativePath: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case relativePath = "relative_path"
            case error
        }
    }

    private func post(_ url: URL, form: [String: String]?) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let form {
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            var components = URLComponents()
            components.queryItems = form.map { key, value in
                URLQueryItem(name: key, value: value)
            }
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LibraryAttachmentError.server("Server returned HTTP \(status)")
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }
}

struct ICloudAttachmentPlacer: Sendable {
    var plan: @Sendable (String) async throws -> String
    var commit: @Sendable (String, String) async throws -> Void
    var release: @Sendable (String) async throws -> Void
    var libraryRoot: URL

    static let system = ICloudAttachmentPlacer(
        plan: { citekey in try await LibraryAttachmentClient.system.plan(citekey: citekey) },
        commit: { citekey, path in
            try await LibraryAttachmentClient.system.commit(
                citekey: citekey,
                relativePath: path
            )
        },
        release: { citekey in try await LibraryAttachmentClient.system.release(citekey: citekey) },
        libraryRoot: LibraryPDFLocator.default.libraryRoot
    )

    static func destination(libraryRoot: URL, relativePath: String) -> URL? {
        guard relativePath.hasPrefix("attachments/"),
              !relativePath.contains(".."),
              relativePath.split(separator: "/").count == 2,
              relativePath.lowercased().hasSuffix(".pdf")
        else { return nil }
        return libraryRoot.appendingPathComponent(relativePath)
    }

    func place(stagedPDF: URL, citekey: String) async throws -> URL {
        let relativePath = try await plan(citekey)
        guard let destination = Self.destination(
            libraryRoot: libraryRoot,
            relativePath: relativePath
        ) else {
            throw LibraryAttachmentError.invalidPath(relativePath)
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: stagedPDF, to: destination)
        do {
            try await commit(citekey, relativePath)
        } catch {
            throw error
        }
        try? await release(citekey)
        return destination
    }
}

struct LibraryPDFMaterializer: Sendable {
    var libraryRoot: URL
    var download: @Sendable (String) async throws -> Data
    var release: @Sendable (String) async throws -> Void
    var startICloudDownload: @Sendable (URL) -> Void

    static let system = LibraryPDFMaterializer(
        libraryRoot: LibraryPDFLocator.default.libraryRoot,
        download: { citekey in try await LibraryAttachmentClient.system.pdfData(citekey: citekey) },
        release: { citekey in try await LibraryAttachmentClient.system.release(citekey: citekey) },
        startICloudDownload: { url in
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    )

    func prepare(record: LibraryRecord) async -> LibraryPDFAvailability {
        guard let attachment = record.attachments.first(where: { $0.kind == "main" })
                ?? record.attachments.first,
              let destination = ICloudAttachmentPlacer.destination(
                libraryRoot: libraryRoot,
                relativePath: attachment.path
              )
        else { return .noAttachment }

        if Self.isEvictedICloudItem(destination) {
            startICloudDownload(destination)
            return .downloadingFromICloud
        }
        if Self.isReadablePDF(destination) {
            return .ready(destination)
        }
        do {
            let data = try await download(record.citekey)
            guard data.starts(with: Data("%PDF-".utf8)) else { return .unavailable }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
        } catch {
            return .unavailable
        }
        guard Self.isReadablePDF(destination) else { return .unavailable }
        try? await release(record.citekey)
        return .ready(destination)
    }

    static func isReadablePDF(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = try? handle.read(upToCount: 5)
        return prefix == Data("%PDF-".utf8)
    }

    static func isEvictedICloudItem(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        guard values?.isUbiquitousItem == true else { return false }
        return values?.ubiquitousItemDownloadingStatus != .current
    }
}
