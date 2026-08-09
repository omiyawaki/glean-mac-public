import Foundation

struct BacklogSnapshotCache {
    let url: URL

    static var `default`: BacklogSnapshotCache {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return BacklogSnapshotCache(
            url: base
                .appendingPathComponent("Glean", isDirectory: true)
                .appendingPathComponent("BacklogSnapshot.json")
        )
    }

    func load() async throws -> BacklogResponse? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BacklogResponse.self, from: data)
    }

    func save(_ response: BacklogResponse) async throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(response).write(to: url, options: [.atomic])
    }
}
