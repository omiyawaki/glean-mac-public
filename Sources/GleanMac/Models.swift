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

struct LibraryAttachment: Codable, Hashable {
    let path: String
    let kind: String
}

/// Detail-pane payload from /api/papers/<citekey>. Most fields are
/// optional because not every record has them filled in.
struct LibraryRecord: Codable, Hashable, Identifiable {
    let citekey: String
    let type: String?
    let title: String
    let year: Int?
    let doi: String?
    let arxiv: String?
    let isbn: String?
    let pmid: String?
    let pmcid: String?
    let journal: String?
    let volume: String?
    let issue: String?
    let pages: String?
    let publisher: String?
    let url: String?
    let abstract: String?
    let keywords: [String]
    let authors: [LibraryAuthor]
    let attachments: [LibraryAttachment]
    let addedAt: String?
    let modifiedAt: String?
    let read: Bool
    let notes: String?

    var id: String { citekey }

    enum CodingKeys: String, CodingKey {
        case citekey, type, title, year, doi, arxiv, isbn, pmid, pmcid
        case journal, volume, issue, pages, publisher, url, abstract
        case keywords, authors, attachments, read, notes
        case addedAt = "added_at"
        case modifiedAt = "modified_at"
    }
}

