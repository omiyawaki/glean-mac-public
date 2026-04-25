import Foundation

struct BacklogEntry: Codable, Identifiable, Hashable {
    let citekey: String
    let doi: String
    let title: String
    let addedAt: Date
    let lastAttemptAt: Date?
    let tried: [String]

    var id: String { doi }

    enum CodingKeys: String, CodingKey {
        case citekey, doi, title, tried
        case addedAt = "added_at"
        case lastAttemptAt = "last_attempt_at"
    }
}

struct BacklogResponse: Codable {
    let count: Int
    let entries: [BacklogEntry]
}
