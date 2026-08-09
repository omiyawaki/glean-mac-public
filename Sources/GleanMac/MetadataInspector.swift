import SwiftUI

/// Right-side inspector pane (Cmd+I). Renders read-only metadata for
/// the current selection. Two flavors — one for Library records, one
/// for Backlog entries — selected by the active sidebar section in
/// ContentView. Form + LabeledContent gives the standard
/// System-Settings-style two-column key/value layout.

struct LibraryMetadataInspector: View {
    let record: LibraryRecord?

    var body: some View {
        if let record {
            Form {
                Section("Identification") {
                    LabeledContent("Citekey") {
                        Text(record.citekey).textSelection(.enabled)
                    }
                    if let v = nonEmpty(record.doi) {
                        LabeledContent("DOI") { Text(v).textSelection(.enabled) }
                    }
                    if let v = nonEmpty(record.arxiv) {
                        LabeledContent("arXiv") { Text(v).textSelection(.enabled) }
                    }
                    if let v = nonEmpty(record.pmid) {
                        LabeledContent("PMID") { Text(v).textSelection(.enabled) }
                    }
                }
                Section("Bibliographic") {
                    if let v = nonEmpty(record.type) {
                        LabeledContent("Type", value: v)
                    }
                    if let v = nonEmpty(record.journal) {
                        LabeledContent("Journal", value: v)
                    }
                    if let year = record.year {
                        LabeledContent("Year", value: String(year))
                    }
                    if let publishedAt = nonEmpty(record.publishedAt) {
                        LabeledContent("Published", value: publishedAt)
                    }
                    if let v = nonEmpty(record.volume) {
                        LabeledContent("Volume", value: v)
                    }
                    if let v = nonEmpty(record.issue) {
                        LabeledContent("Issue", value: v)
                    }
                    if let v = nonEmpty(record.pages) {
                        LabeledContent("Pages", value: v)
                    }
                    if let v = nonEmpty(record.publisher) {
                        LabeledContent("Publisher", value: v)
                    }
                }
                if !record.authors.isEmpty {
                    Section("Authors") {
                        ForEach(Array(record.authors.enumerated()), id: \.offset) { (_, a) in
                            Text(formatAuthor(a))
                        }
                    }
                }
                if !record.keywords.isEmpty {
                    Section("Keywords") {
                        Text(record.keywords.joined(separator: ", "))
                    }
                }
                if let abstract = nonEmpty(record.abstract) {
                    Section("Abstract") {
                        Text(abstract).textSelection(.enabled)
                    }
                }
                if let notes = nonEmpty(record.notes) {
                    Section("Notes") {
                        Text(notes).textSelection(.enabled)
                    }
                }
                Section("Dates") {
                    if let v = nonEmpty(record.addedAt) {
                        LabeledContent("Added", value: v)
                    }
                    if let v = nonEmpty(record.modifiedAt) {
                        LabeledContent("Modified", value: v)
                    }
                    LabeledContent("Read", value: record.read ? "Yes" : "No")
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No record loaded",
                systemImage: "info.circle"
            )
        }
    }

    private func formatAuthor(_ a: LibraryAuthor) -> String {
        if a.given.isEmpty { return a.family }
        return "\(a.family), \(a.given)"
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}

struct BacklogMetadataInspector: View {
    let entry: BacklogEntry?

    var body: some View {
        if let entry {
            Form {
                Section("Identification") {
                    LabeledContent("Citekey") {
                        Text(entry.citekey).textSelection(.enabled)
                    }
                    LabeledContent("DOI") {
                        Text(entry.doi).textSelection(.enabled)
                    }
                }
                Section("Status") {
                    LabeledContent("Added") {
                        Text(entry.addedAt, style: .date)
                    }
                    if let lastAttempt = entry.lastAttemptAt {
                        LabeledContent("Last attempt") {
                            Text(lastAttempt, style: .relative)
                        }
                    }
                }
                if !entry.tried.isEmpty {
                    Section("Tried URLs") {
                        ForEach(entry.tried, id: \.self) { url in
                            Text(url)
                                .font(.callout)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No entry selected",
                systemImage: "info.circle"
            )
        }
    }
}
