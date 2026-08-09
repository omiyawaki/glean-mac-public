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
    let publishedAt: String?
    let addedAt: String?
    let doi: String?
    let authors: [LibraryAuthor]

    var id: String { citekey }

    // Public initializer used by LocalLibraryIndexReader (local SQLite path)
    init(
        citekey: String,
        title: String,
        year: Int?,
        publishedAt: String? = nil,
        addedAt: String? = nil,
        doi: String?,
        authors: [LibraryAuthor]
    ) {
        self.citekey = citekey
        self.title = LibraryEntry.cleanedTitle(title)
        self.year = year
        self.publishedAt = publishedAt
        self.addedAt = addedAt
        self.doi = doi
        self.authors = authors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        citekey = try container.decode(String.self, forKey: .citekey)
        let rawTitle = try container.decode(String.self, forKey: .title)
        title = LibraryEntry.cleanedTitle(rawTitle)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        addedAt = try container.decodeIfPresent(String.self, forKey: .addedAt)
        doi = try container.decodeIfPresent(String.self, forKey: .doi)
        authors = try container.decode([LibraryAuthor].self, forKey: .authors)
    }

    // CodingKeys only needed because we have a custom init(from:)
    private enum CodingKeys: String, CodingKey {
        case citekey, title, year, doi, authors
        case publishedAt = "published_at"
        case addedAt = "added_at"
    }
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
    let publishedAt: String?
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

    // Public memberwise initializer (used by tests and any direct construction).
    // Applies defensive title cleaning.
    init(
        citekey: String,
        type: String?,
        title: String,
        year: Int?,
        publishedAt: String? = nil,
        doi: String?,
        arxiv: String?,
        isbn: String?,
        pmid: String?,
        pmcid: String?,
        journal: String?,
        volume: String?,
        issue: String?,
        pages: String?,
        publisher: String?,
        url: String?,
        abstract: String?,
        keywords: [String],
        authors: [LibraryAuthor],
        attachments: [LibraryAttachment],
        addedAt: String?,
        modifiedAt: String?,
        read: Bool,
        notes: String?
    ) {
        self.citekey = citekey
        self.type = type
        self.title = LibraryRecord.cleanedTitle(title)
        self.year = year
        self.publishedAt = publishedAt
        self.doi = doi
        self.arxiv = arxiv
        self.isbn = isbn
        self.pmid = pmid
        self.pmcid = pmcid
        self.journal = journal
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.publisher = publisher
        self.url = url
        self.abstract = abstract
        self.keywords = keywords
        self.authors = authors
        self.attachments = attachments
        self.addedAt = addedAt
        self.modifiedAt = modifiedAt
        self.read = read
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        citekey = try container.decode(String.self, forKey: .citekey)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        let rawTitle = try container.decode(String.self, forKey: .title)
        title = LibraryRecord.cleanedTitle(rawTitle)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        doi = try container.decodeIfPresent(String.self, forKey: .doi)
        arxiv = try container.decodeIfPresent(String.self, forKey: .arxiv)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        pmid = try container.decodeIfPresent(String.self, forKey: .pmid)
        pmcid = try container.decodeIfPresent(String.self, forKey: .pmcid)
        journal = try container.decodeIfPresent(String.self, forKey: .journal)
        volume = try container.decodeIfPresent(String.self, forKey: .volume)
        issue = try container.decodeIfPresent(String.self, forKey: .issue)
        pages = try container.decodeIfPresent(String.self, forKey: .pages)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        abstract = try container.decodeIfPresent(String.self, forKey: .abstract)
        keywords = try container.decode([String].self, forKey: .keywords)
        authors = try container.decode([LibraryAuthor].self, forKey: .authors)
        attachments = try container.decode([LibraryAttachment].self, forKey: .attachments)
        addedAt = try container.decodeIfPresent(String.self, forKey: .addedAt)
        modifiedAt = try container.decodeIfPresent(String.self, forKey: .modifiedAt)
        read = try container.decode(Bool.self, forKey: .read)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    enum CodingKeys: String, CodingKey {
        case citekey, type, title, year, doi, arxiv, isbn, pmid, pmcid
        case publishedAt = "published_at"
        case journal, volume, issue, pages, publisher, url, abstract
        case keywords, authors, attachments, read, notes
        case addedAt = "added_at"
        case modifiedAt = "modified_at"
    }
}

// MARK: - Defensive title sanitization (protects against <scp>, <jats:...>, etc.
// that can leak from Crossref/JATS publisher deposits into Glean metadata)
extension LibraryEntry {
    /// Strips common HTML/XML markup from titles (e.g. <scp>North Atlantic Oscillation</scp>)
    /// and normalizes whitespace. This is a defensive belt-and-suspenders layer for
    /// any records that were ingested before the Python-side strip_markup fix landed.
    /// New records should already be clean at ingest time.
    static func cleanedTitle(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        // Remove any <tag> or </tag> fragments (simple, fast, sufficient for this pollution)
        let tagStripped = raw.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        // Collapse runs of whitespace (including after tag removal)
        let normalized = tagStripped.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
    }
}

extension LibraryRecord {
    /// Same defensive cleaning for the full record detail path.
    static func cleanedTitle(_ raw: String) -> String {
        LibraryEntry.cleanedTitle(raw)
    }
}
