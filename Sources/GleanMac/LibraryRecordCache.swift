import Foundation

/// Small, local-only cache for complete library records. The list endpoint
/// intentionally omits attachment paths, so without this cache every paper
/// selection has to wait for the backend API before the PDF view can be built.
///
/// Records remain authoritative on the backend service. This cache only enables
/// stale-while-revalidate display and is safe to delete or rebuild at any time.
struct LibraryRecordCache {
    struct Entry: Codable {
        let record: LibraryRecord
        var lastAccessedAt: Date
    }

    private struct Snapshot: Codable {
        let version: Int
        let entries: [Entry]
    }

    static let currentVersion = 1
    static let defaultMaximumRecordCount = 64

    let url: URL
    let maximumRecordCount: Int

    static var `default`: LibraryRecordCache {
        let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return LibraryRecordCache(
            url: base
                .appendingPathComponent("Glean", isDirectory: true)
                .appendingPathComponent("LibraryRecords.json"),
            maximumRecordCount: defaultMaximumRecordCount
        )
    }

    init(url: URL, maximumRecordCount: Int = defaultMaximumRecordCount) {
        self.url = url
        self.maximumRecordCount = max(1, maximumRecordCount)
    }

    func load() throws -> [String: Entry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        guard snapshot.version == Self.currentVersion else { return [:] }
        var records: [String: Entry] = [:]
        for entry in trimmed(snapshot.entries) {
            // A corrupt or manually edited cache may contain the same citekey
            // more than once. Keep the first (most recently accessed) value
            // instead of trapping in Dictionary(uniqueKeysWithValues:).
            if records[entry.record.citekey] == nil {
                records[entry.record.citekey] = entry
            }
        }
        return records
    }

    func encoded(_ records: [String: Entry]) throws -> Data {
        let snapshot = Snapshot(
            version: Self.currentVersion,
            entries: trimmed(Array(records.values))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    func save(_ records: [String: Entry]) throws {
        try write(encoded(records))
    }

    func write(_ data: Data) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    private func trimmed(_ entries: [Entry]) -> [Entry] {
        Array(
            entries
                .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
                .prefix(maximumRecordCount)
        )
    }
}

/// Serializes atomic cache writes off the main actor. A generation check also
/// prevents a delayed older snapshot from overwriting a newer one.
private actor LibraryRecordCacheWriter {
    let cache: LibraryRecordCache
    private var latestGeneration = 0

    init(cache: LibraryRecordCache) {
        self.cache = cache
    }

    func write(_ data: Data, generation: Int) {
        guard generation >= latestGeneration else { return }
        latestGeneration = generation
        try? cache.write(data)
    }
}

@MainActor
final class LibraryRecordCacheStore {
    private let cache: LibraryRecordCache
    private let writer: LibraryRecordCacheWriter
    private var entries: [String: LibraryRecordCache.Entry]
    private var writeGeneration = 0

    init(cache: LibraryRecordCache = .default) {
        self.cache = cache
        writer = LibraryRecordCacheWriter(cache: cache)
        entries = (try? cache.load()) ?? [:]
    }

    func record(for citekey: String) -> LibraryRecord? {
        entries[citekey]?.record
    }

    func touch(_ citekey: String, at date: Date = Date()) {
        guard var entry = entries[citekey] else { return }
        entry.lastAccessedAt = date
        entries[citekey] = entry
    }

    func insert(_ record: LibraryRecord, at date: Date = Date()) {
        entries[record.citekey] = LibraryRecordCache.Entry(
            record: record,
            lastAccessedAt: date
        )
        persist()
    }

    private func persist() {
        guard let data = try? cache.encoded(entries) else { return }
        writeGeneration &+= 1
        let generation = writeGeneration
        let writer = writer
        Task {
            await writer.write(data, generation: generation)
        }
    }
}
