import AppKit
import PDFKit
import XCTest
@testable import GleanMac

/// Opt-in audit against Osamu's real library. The normal test suite skips this
/// because it intentionally opens hundreds of user PDFs. Run with:
///
///     GLEAN_LIBRARY_PDF_AUDIT=1 swift test \
///       --filter PDFDarkModeLibraryAuditTests
///
/// The audit selects one local PDF for every normalized journal represented in
/// the library and validates its transition surface before PDFKit receives the
/// document. It then performs a small first-page dark raster across an evenly
/// stratified journal subset, always including known regressions, to catch
/// format- or publisher-specific rendering failures without letting one
/// pathological book stall the complete transition survey.
@MainActor
final class PDFDarkModeLibraryAuditTests: XCTestCase {
    private struct Candidate {
        let journal: String
        let citekey: String
        let pdfURL: URL
        let fileSize: Int
    }

    private struct RenderResult {
        let candidate: Candidate
        let durationMilliseconds: Double
        let nearWhiteFraction: Double
    }

    private final class DarkPageDelegate: NSObject, PDFDocumentDelegate {
        func classForPage() -> AnyClass {
            InvertedPDFPage.self
        }
    }

    func testAllJournalsHaveProtectedTransitionAndStratifiedRastersAreDark() throws {
        guard ProcessInfo.processInfo.environment["GLEAN_LIBRARY_PDF_AUDIT"] == "1" else {
            throw XCTSkip("Set GLEAN_LIBRARY_PDF_AUDIT=1 to scan the real paper library.")
        }

        let libraryRoot = URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["GLEAN_LIBRARY_ROOT"]
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Documents/glean", isDirectory: true).path,
            isDirectory: true
        )
        let candidatesByJournal = try loadCandidates(libraryRoot: libraryRoot)
        XCTAssertGreaterThan(
            candidatesByJournal.count,
            100,
            "The audit should cover the breadth of the real library."
        )

        let view = PDFThumbnailSplitView(configuration: .previewLike)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let sortedGroups = candidatesByJournal.values.sorted {
            $0[0].journal.localizedCaseInsensitiveCompare($1[0].journal) == .orderedAscending
        }
        var transitionFailures: [String] = []

        for group in sortedGroups {
            guard let candidate = group.first else { continue }
            do {
                try auditTransition(candidate: candidate, in: view)
            } catch {
                transitionFailures.append(
                    "\(candidate.journal) / \(candidate.citekey): \(error.localizedDescription)"
                )
            }
        }

        // Real first-page rasterization is substantially more expensive and
        // can block inside PDFKit for malformed or book-length files. Sample
        // journals evenly, prefer compact candidate files, and force the two
        // papers that originally exposed the behavioral difference.
        let renderGroups = stratifiedRenderGroups(from: sortedGroups)
        var results: [RenderResult] = []
        var renderFailures: [String] = []

        for (index, group) in renderGroups.enumerated() {
            var groupFailures: [String] = []
            var result: RenderResult?

            for candidate in group {
                do {
                    result = try auditRaster(candidate: candidate)
                    break
                } catch {
                    groupFailures.append("\(candidate.citekey): \(error.localizedDescription)")
                }
            }

            if let result {
                results.append(result)
            } else if let journal = group.first?.journal {
                renderFailures.append("\(journal): \(groupFailures.joined(separator: "; "))")
            }

            if (index + 1).isMultiple(of: 25) {
                print(
                    "GLEAN_DARK_PDF_AUDIT raster_progress=\(index + 1)/\(renderGroups.count) "
                        + "rendered=\(results.count) failures=\(renderFailures.count)"
                )
            }
        }

        let nearlyWhite = results.filter { $0.nearWhiteFraction >= 0.90 }
        let slowest = results
            .sorted { $0.durationMilliseconds > $1.durationMilliseconds }
            .prefix(10)
            .map {
                "\($0.candidate.citekey)=\(String(format: "%.1f", $0.durationMilliseconds))ms"
            }
            .joined(separator: ", ")
        let highestWhiteFractions = results
            .sorted { $0.nearWhiteFraction > $1.nearWhiteFraction }
            .prefix(10)
            .map {
                "\($0.candidate.citekey)=\(String(format: "%.3f", $0.nearWhiteFraction))"
            }
            .joined(separator: ", ")

        print(
            "GLEAN_DARK_PDF_AUDIT journals=\(candidatesByJournal.count) "
                + "protected=\(candidatesByJournal.count - transitionFailures.count) "
                + "rendered=\(results.count) transition_failures=\(transitionFailures.count) "
                + "render_failures=\(renderFailures.count) "
                + "near_white=\(nearlyWhite.count)"
        )
        print("GLEAN_DARK_PDF_AUDIT slowest=\(slowest)")
        print("GLEAN_DARK_PDF_AUDIT highest_white_fractions=\(highestWhiteFractions)")

        XCTAssertTrue(
            transitionFailures.isEmpty,
            transitionFailures.prefix(20).joined(separator: "\n")
        )
        XCTAssertTrue(
            renderFailures.isEmpty,
            renderFailures.prefix(20).joined(separator: "\n")
        )
        XCTAssertTrue(
            nearlyWhite.isEmpty,
            nearlyWhite.prefix(20).map {
                "\($0.candidate.journal) / \($0.candidate.citekey): "
                    + String(format: "%.3f near-white", $0.nearWhiteFraction)
            }.joined(separator: "\n")
        )
    }

    private func auditTransition(
        candidate: Candidate,
        in view: PDFThumbnailSplitView
    ) throws {
        let descriptor = PDFFileCacheDescriptor(url: candidate.pdfURL)
        _ = view.prepareForDocument(
            url: candidate.pdfURL,
            descriptor: descriptor,
            darkMode: true
        )
        view.displayTransitionCoverIfNeeded()
        defer { view.cancelDocumentTransition() }

        guard view.isTransitionCoverVisible,
              view.isTransitionCoverOpaque,
              grayLevel(of: view.transitionCoverBackgroundColor)
                <= PDFDarkModePalette.pageBackgroundLevel + 0.04
        else {
            throw AuditError.unprotectedTransition
        }
    }

    private func auditRaster(candidate: Candidate) throws -> RenderResult {
        let delegate = DarkPageDelegate()
        guard let document = PDFDocument(url: candidate.pdfURL) else {
            throw AuditError.cannotOpenPDF
        }
        document.delegate = delegate
        guard let page = document.page(at: 0) as? InvertedPDFPage else {
            throw AuditError.missingDarkPage
        }

        let startedAt = ContinuousClock.now
        guard let image = PDFThumbnailRasterizer.thumbnail(
            page: page,
            displaySize: CGSize(width: 72, height: 96),
            box: .cropBox,
            renderScale: 1
        ) else {
            throw AuditError.cannotRasterPage
        }
        let duration = startedAt.duration(to: .now) / .milliseconds(1)

        return RenderResult(
            candidate: candidate,
            durationMilliseconds: duration,
            nearWhiteFraction: try nearWhiteFraction(in: image)
        )
    }

    private func loadCandidates(libraryRoot: URL) throws -> [String: [Candidate]] {
        let recordsDirectory = libraryRoot.appendingPathComponent("records", isDirectory: true)
        let recordURLs = try FileManager.default.contentsOfDirectory(
            at: recordsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "yaml" }
        var groups: [String: [Candidate]] = [:]

        for recordURL in recordURLs {
            let text = try String(contentsOf: recordURL, encoding: .utf8)
            guard let metadata = parseRecord(text),
                  !metadata.journal.isEmpty
            else { continue }

            for attachmentPath in metadata.attachmentPaths {
                let pdfURL: URL
                if attachmentPath.hasPrefix("/") {
                    pdfURL = URL(fileURLWithPath: attachmentPath)
                } else {
                    pdfURL = libraryRoot.appendingPathComponent(attachmentPath)
                }
                guard pdfURL.pathExtension.lowercased() == "pdf",
                      FileManager.default.fileExists(atPath: pdfURL.path)
                else { continue }

                let candidate = Candidate(
                    journal: metadata.journal,
                    citekey: metadata.citekey,
                    pdfURL: pdfURL,
                    fileSize: ((try? pdfURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
                )
                groups[normalizedJournalKey(metadata.journal), default: []].append(candidate)
                break
            }
        }
        return groups
    }

    private func stratifiedRenderGroups(
        from sortedGroups: [[Candidate]],
        targetCount: Int = 96,
        maximumPreferredFileSize: Int = 10 * 1_024 * 1_024
    ) -> [[Candidate]] {
        let eligibleGroups = sortedGroups.compactMap { group -> [Candidate]? in
            let eligible = group
                .filter { $0.fileSize > 0 && $0.fileSize <= maximumPreferredFileSize }
                .sorted { $0.fileSize < $1.fileSize }
            return eligible.isEmpty ? nil : eligible
        }
        guard !eligibleGroups.isEmpty else { return [] }

        let sampleCount = min(targetCount, eligibleGroups.count)
        var selected: [[Candidate]] = []
        var selectedCitekeys: Set<String> = []
        for offset in 0..<sampleCount {
            let index: Int
            if sampleCount == 1 {
                index = 0
            } else {
                index = offset * (eligibleGroups.count - 1) / (sampleCount - 1)
            }
            let group = eligibleGroups[index]
            selected.append(group)
            selectedCitekeys.insert(group[0].citekey)
        }

        let forcedCitekeys = ["Huang2026Response", "Huang2026Underestimated"]
        for citekey in forcedCitekeys where !selectedCitekeys.contains(citekey) {
            if let candidate = sortedGroups.lazy.flatMap({ $0 }).first(where: { $0.citekey == citekey }) {
                selected.append([candidate])
                selectedCitekeys.insert(citekey)
            }
        }
        return selected
    }

    private func parseRecord(
        _ text: String
    ) -> (citekey: String, journal: String, attachmentPaths: [String])? {
        var citekey: String?
        var journal: String?
        var attachmentPaths: [String] = []
        var insideAttachments = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let isTopLevel = line.first.map { !$0.isWhitespace } ?? false

            if isTopLevel {
                insideAttachments = line == "attachments:"
                if line.hasPrefix("citekey:") {
                    citekey = yamlScalar(String(line.dropFirst("citekey:".count)))
                } else if line.hasPrefix("journal:") {
                    journal = yamlScalar(String(line.dropFirst("journal:".count)))
                }
                continue
            }

            if insideAttachments {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- path:") {
                    let path = yamlScalar(String(trimmed.dropFirst("- path:".count)))
                    if !path.isEmpty {
                        attachmentPaths.append(path)
                    }
                }
            }
        }

        guard let citekey, let journal else { return nil }
        return (citekey, journal, attachmentPaths)
    }

    private func yamlScalar(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        guard value != "null", value != "~" else { return "" }
        if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            if let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) {
                return decoded
            }
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private func normalizedJournalKey(_ journal: String) -> String {
        journal
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func grayLevel(of color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
    }

    private func nearWhiteFraction(in image: NSImage) throws -> Double {
        let cgImage = try XCTUnwrap(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AuditError.cannotReadPixels
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var visiblePixels = 0
        var nearWhitePixels = 0
        var offset = 0
        while offset < pixels.count {
            let alpha = pixels[offset + 3]
            if alpha >= 230 {
                visiblePixels += 1
                if pixels[offset] >= 235,
                   pixels[offset + 1] >= 235,
                   pixels[offset + 2] >= 235 {
                    nearWhitePixels += 1
                }
            }
            offset += bytesPerPixel
        }
        guard visiblePixels > 0 else { throw AuditError.cannotReadPixels }
        return Double(nearWhitePixels) / Double(visiblePixels)
    }

    private enum AuditError: LocalizedError {
        case unprotectedTransition
        case cannotOpenPDF
        case missingDarkPage
        case cannotRasterPage
        case cannotReadPixels

        var errorDescription: String? {
            switch self {
            case .unprotectedTransition:
                "dark transition cover was not visible, opaque, and dark"
            case .cannotOpenPDF:
                "PDFKit could not open the PDF"
            case .missingDarkPage:
                "PDFKit did not construct the app's inverted page class"
            case .cannotRasterPage:
                "the first page could not be rasterized"
            case .cannotReadPixels:
                "the raster pixels could not be inspected"
            }
        }
    }
}
