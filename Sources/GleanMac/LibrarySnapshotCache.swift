import Foundation

struct LibrarySnapshotCache {
    let url: URL

    static var `default`: LibrarySnapshotCache {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return LibrarySnapshotCache(
            url: base
                .appendingPathComponent("Glean", isDirectory: true)
                .appendingPathComponent("LibrarySnapshot.json")
        )
    }

    func load() async throws -> LibraryResponse? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LibraryResponse.self, from: data)
    }

    func save(_ response: LibraryResponse) async throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(response)
        try data.write(to: url, options: [.atomic])
    }
}
