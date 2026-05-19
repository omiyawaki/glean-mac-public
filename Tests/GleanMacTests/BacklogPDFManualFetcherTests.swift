import XCTest
@testable import GleanMac

@MainActor
final class BacklogPDFManualFetcherTests: XCTestCase {
    func testManualFetchPresentationRequiresDOI() {
        let entry = BacklogEntry(
            citekey: "Xu2026Multidecadal",
            doi: "10.1016/j.aosl.2026.100852",
            title: "Multidecadal variability",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )
        let entryWithoutDOI = BacklogEntry(
            citekey: "NoDOI2026",
            doi: "",
            title: "No DOI",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )

        XCTAssertTrue(BacklogPDFManualFetchPresentation.isAvailable(for: entry))
        XCTAssertFalse(BacklogPDFManualFetchPresentation.isAvailable(for: entryWithoutDOI))
        XCTAssertFalse(BacklogPDFManualFetchPresentation.isAvailable(for: nil))
    }

    func testManualFetchPresentationNamesMenuAndToolbarCommands() {
        XCTAssertEqual(BacklogPDFManualFetchPresentation.menuTitle, "Try Fetching PDF")
        XCTAssertEqual(BacklogPDFManualFetchPresentation.toolbarTitle, "Find PDF")
    }

    func testFetchPDFSelectsEntryBeforeRunningForegroundWebActions() async {
        let entry = BacklogEntry(
            citekey: "Xu2026Multidecadal",
            doi: "10.1016/j.aosl.2026.100852",
            title: "Multidecadal variability",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )
        let capture = BacklogFetchActionCapture()
        let fetcher = BacklogPDFManualFetcher(
            runAction: { id, payload in
                await capture.record(id: id, payload: payload)
            },
            sleep: { _ in }
        )

        await fetcher.fetchPDF(for: entry)

        XCTAssertEqual(
            capture.calls.map(\.id),
            [
                "backlog.selectByID",
                "web.clickPDFLink",
            ]
        )
        XCTAssertEqual(capture.calls.first?.payload?["id"] as? String, entry.id)
    }

    func testFetchPDFUsesCurrentWebViewWithoutReselectingAlreadySelectedEntry() async {
        let entry = BacklogEntry(
            citekey: "Xu2026Multidecadal",
            doi: "10.1016/j.aosl.2026.100852",
            title: "Multidecadal variability",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )
        let capture = BacklogFetchActionCapture()
        let fetcher = BacklogPDFManualFetcher(
            runAction: { id, payload in
                await capture.record(id: id, payload: payload)
            },
            sleep: { _ in }
        )

        await fetcher.fetchPDF(for: entry, isAlreadySelected: true)

        XCTAssertEqual(
            capture.calls.map(\.id),
            [
                "web.clickPDFLink",
            ]
        )
    }

    func testFetchPDFSkipsEntriesWithoutDOI() async {
        let entry = BacklogEntry(
            citekey: "NoDOI2026",
            doi: "",
            title: "No DOI",
            addedAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: nil,
            tried: []
        )
        let capture = BacklogFetchActionCapture()
        let fetcher = BacklogPDFManualFetcher(
            runAction: { id, payload in
                await capture.record(id: id, payload: payload)
            },
            sleep: { _ in }
        )

        await fetcher.fetchPDF(for: entry)

        XCTAssertTrue(capture.calls.isEmpty)
    }
}

@MainActor
private final class BacklogFetchActionCapture {
    struct Call {
        let id: String
        let payload: [String: Any]?
    }

    private(set) var calls: [Call] = []

    func record(id: String, payload: [String: Any]?) async -> Bool {
        calls.append(Call(id: id, payload: payload))
        return true
    }
}
