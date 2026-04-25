import Foundation

// MARK: - Backlog

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

// MARK: - Maybe Review (the worker's "ask the human" queue)

struct ReviewEntry: Codable, Identifiable, Hashable {
    let doi: String
    let url: String
    let title: String
    let authors: String
    let journal: String
    let confidence: String
    let queuedAt: String
    let reasoning: String

    var id: String { doi }

    enum CodingKeys: String, CodingKey {
        case doi, url, title, authors, journal, confidence, reasoning
        case queuedAt = "queued_at"
    }
}

struct ReviewResponse: Codable {
    let count: Int
    let entries: [ReviewEntry]
}

// MARK: - Author Proposals

struct AuthorSample: Codable, Hashable {
    let doi: String
    let title: String
}

struct AuthorProposal: Codable, Identifiable, Hashable {
    let author: String
    let count: Int
    let samples: [AuthorSample]

    var id: String { author }
}

struct AuthorProposalsResponse: Codable {
    let count: Int
    let entries: [AuthorProposal]
}

// MARK: - Library

struct LibraryAuthor: Codable, Hashable {
    let family: String
    let given: String
}

struct LibraryEntry: Codable, Identifiable, Hashable {
    let citekey: String
    let title: String
    let year: Int?
    let doi: String?
    let authors: [LibraryAuthor]

    var id: String { citekey }
}

struct LibraryResponse: Codable {
    let count: Int
    let entries: [LibraryEntry]
}

