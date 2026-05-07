import Foundation

enum WebPDFDownloadPolicy {
    static func isPDF(mimeType: String?, url: URL?) -> Bool {
        if let mimeType {
            let normalized = mimeType
                .split(separator: ";", maxSplits: 1)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalized == "application/pdf" {
                return true
            }
        }

        return url?.pathExtension.lowercased() == "pdf"
    }

    static func destinationURL(
        suggestedFilename: String?,
        responseURL: URL?,
        downloadsDirectory: URL = WebPDFDownloadPolicy.defaultDestinationDirectory,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let rawFilename = suggestedFilename?.nilIfEmpty
            ?? responseURL?.lastPathComponent.nilIfEmpty
            ?? "download.pdf"
        let filename = rawFilename.lowercased().hasSuffix(".pdf")
            ? rawFilename
            : "\(rawFilename).pdf"
        let baseURL = downloadsDirectory.appendingPathComponent(filename)
        guard fileExists(baseURL) else { return baseURL }

        let extensionPart = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        for index in 2... {
            let candidate = downloadsDirectory
                .appendingPathComponent("\(stem) \(index)")
                .appendingPathExtension(extensionPart)
            if !fileExists(candidate) {
                return candidate
            }
        }

        return baseURL
    }

    private static var defaultDestinationDirectory: URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        let directory = caches
            .appendingPathComponent("GleanMac", isDirectory: true)
            .appendingPathComponent("PDF Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "/" ? nil : trimmed
    }
}
