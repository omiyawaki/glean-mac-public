import Foundation

// MARK: - Backlog

struct BacklogEntry: Codable, Identifiable, Hashable {
    enum State: String, Codable {
        case missingPDF = "missing_pdf"
        case automatedFetchPending = "automated_fetch_pending"
        case automatedFetchFailed = "automated_fetch_failed"
        case manualRetrievalNeeded = "manual_retrieval_needed"
        case attachmentFileMissing = "attachment_file_missing"
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = State(rawValue: rawValue) ?? .unknown
        }
    }

    let citekey: String
    let doi: String
    let title: String
    let addedAt: Date
    let lastAttemptAt: Date?
    let tried: [String]
    let state: State
    let source: String
    let missingAttachmentPaths: [String]

    /// SwiftUI's List + ForEach require Identifiable rows to have
    /// unique IDs; identical IDs cause the list to render N copies of
    /// the same row's content rather than N distinct rows. Backlog
    /// entries without a DOI (books, non-DOI items like the Smithsonian
    /// Meteorological Tables) would otherwise all collide on id="",
    /// so the sidebar showed e.g. five rows of "Smithsonian
    /// Meteorological Tables" when it should have showed Chakraborty,
    /// Chan, Hell, Lam, and List once each. Mirror the
    /// `pdf_backlog._save` key format so the SwiftUI id matches the
    /// JSON key for the same entry.
    var id: String { doi.isEmpty ? "citekey:\(citekey)" : doi }

    var statusText: String {
        switch state {
        case .missingPDF:
            "Missing PDF"
        case .automatedFetchPending:
            "Fetch pending"
        case .automatedFetchFailed:
            "Fetch failed"
        case .manualRetrievalNeeded:
            "Manual retrieval needed"
        case .attachmentFileMissing:
            "Attachment file missing"
        case .unknown:
            tried.isEmpty ? "Missing PDF" : "Manual retrieval needed"
        }
    }

    init(citekey: String,
         doi: String,
         title: String,
         addedAt: Date,
         lastAttemptAt: Date?,
         tried: [String],
         state: State = .unknown,
         source: String = "",
         missingAttachmentPaths: [String] = []) {
        self.citekey = citekey
        self.doi = doi
        self.title = title
        self.addedAt = addedAt
        self.lastAttemptAt = lastAttemptAt
        self.tried = tried
        self.state = state
        self.source = source
        self.missingAttachmentPaths = missingAttachmentPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        citekey = try container.decode(String.self, forKey: .citekey)
        doi = try container.decode(String.self, forKey: .doi)
        title = try container.decode(String.self, forKey: .title)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        tried = try container.decodeIfPresent([String].self, forKey: .tried) ?? []
        state = try container.decodeIfPresent(State.self, forKey: .state) ?? .unknown
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        missingAttachmentPaths = try container.decodeIfPresent(
            [String].self,
            forKey: .missingAttachmentPaths
        ) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case citekey, doi, title, tried, state, source
        case addedAt = "added_at"
        case lastAttemptAt = "last_attempt_at"
        case missingAttachmentPaths = "missing_attachment_paths"
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
