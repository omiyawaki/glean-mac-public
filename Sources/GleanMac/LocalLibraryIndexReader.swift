import Foundation

struct LocalLibraryIndexReader {
    let databaseURL: URL
    let sqliteExecutableURL: URL

    static var `default`: LocalLibraryIndexReader {
        LocalLibraryIndexReader(
            databaseURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/glean/index.sqlite"),
            sqliteExecutableURL: URL(fileURLWithPath: "/usr/bin/sqlite3")
        )
    }

    init(databaseURL: URL,
         sqliteExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/sqlite3")) {
        self.databaseURL = databaseURL
        self.sqliteExecutableURL = sqliteExecutableURL
    }

    func load() async throws -> LibraryResponse? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }
        let records = try runJSONQuery(
            """
            SELECT citekey, title, year, doi
            FROM records
            ORDER BY year IS NULL, year DESC, citekey ASC
            """
        ) as [RecordRow]
        let authors = try runJSONQuery(
            """
            SELECT citekey, family, given
            FROM authors
            ORDER BY citekey, ord
            """
        ) as [AuthorRow]
        var authorsByCitekey: [String: [LibraryAuthor]] = [:]
        for author in authors {
            authorsByCitekey[author.citekey, default: []].append(
                LibraryAuthor(family: author.family,
                              given: author.given ?? "")
            )
        }
        let entries = records.map { row in
            LibraryEntry(
                citekey: row.citekey,
                title: row.title,
                year: row.year,
                doi: row.doi,
                authors: authorsByCitekey[row.citekey] ?? []
            )
        }
        return LibraryResponse(count: entries.count, entries: entries)
    }

    private func runJSONQuery<T: Decodable>(_ sql: String) throws -> [T] {
        let process = Process()
        process.executableURL = sqliteExecutableURL
        process.arguments = ["-json", databaseURL.path, sql]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(
                data: errorData,
                encoding: .utf8
            ) ?? "sqlite3 failed"
            throw LocalIndexError.sqlite(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if data.isEmpty || data.allSatisfy({ byte in
            byte == 0x0a || byte == 0x0d || byte == 0x20 || byte == 0x09
        }) {
            return []
        }
        return try JSONDecoder().decode([T].self, from: data)
    }

    enum LocalIndexError: Error, Equatable {
        case sqlite(String)
    }

    private struct RecordRow: Decodable {
        let citekey: String
        let title: String
        let year: Int?
        let doi: String?
    }

    private struct AuthorRow: Decodable {
        let citekey: String
        let family: String
        let given: String?
    }
}
