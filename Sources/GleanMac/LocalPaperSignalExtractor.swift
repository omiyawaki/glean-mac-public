import Foundation

struct LocalPaperSignalExtractor: Sendable {
    let extractDOICandidates: @Sendable (URL) async throws -> [String]

    static let `default` = LocalPaperSignalExtractor { url in
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return extractDOICandidates(from: text)
    }

    func doiCandidates(in url: URL) async throws -> [String] {
        try await extractDOICandidates(url)
    }

    private static func extractDOICandidates(from text: String) -> [String] {
        let pattern = #"10\.\d{4,9}/[-._;()/:A-Z0-9]+"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen: Set<String> = []
        var candidates: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let raw = String(text[matchRange])
            let candidate = raw.trimmingCharacters(
                in: CharacterSet(charactersIn: ".,;:)]}>\n\r\t ")
            )
            let key = candidate.lowercased()
            guard !candidate.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            candidates.append(candidate)
        }
        return candidates
    }
}
