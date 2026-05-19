import Foundation

struct PendingPDFStager {
    enum StageError: Error, Equatable {
        case notPDF
    }

    let directory: URL

    static var `default`: PendingPDFStager {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return PendingPDFStager(
            directory: base
                .appendingPathComponent("Glean", isDirectory: true)
                .appendingPathComponent("PendingPDFs", isDirectory: true)
        )
    }

    func stage(_ source: URL, id: UUID = UUID()) async throws -> URL {
        guard source.pathExtension.lowercased() == "pdf" else {
            throw StageError.notPDF
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let destination = directory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension("pdf")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
