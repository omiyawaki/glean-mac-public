import XCTest
@testable import GleanMac

final class GleanBackendEndpointsTests: XCTestCase {
    func testHomeEndpointsDeriveEveryBackendRoute() {
        let endpoints = GleanBackendEndpoints.home

        XCTAssertEqual(
            endpoints.eventsURL.absoluteString,
            "http://backend.example.com:8765/events"
        )
        XCTAssertEqual(
            endpoints.backlogURL.absoluteString,
            "http://backend.example.com:8765/api/backlog?scope=global"
        )
        XCTAssertEqual(
            endpoints.intakeURL(path: "/api/review/add").absoluteString,
            "http://backend.example.com:8765/api/review/add"
        )
        XCTAssertEqual(
            endpoints.libraryURL(path: "api/papers").absoluteString,
            "http://backend.example.com:8766/api/papers"
        )
        XCTAssertEqual(
            endpoints.libraryDetailURL(citekey: "Abatzoglou2026Observed").absoluteString,
            "http://backend.example.com:8766/api/papers/Abatzoglou2026Observed"
        )
        XCTAssertEqual(
            endpoints.libraryRelationURL(
                citekey: "Abatzoglou2026Observed",
                kind: .references
            ).absoluteString,
            "http://backend.example.com:8766/api/papers/Abatzoglou2026Observed/references"
        )
        XCTAssertEqual(
            endpoints.libraryRelationURL(
                citekey: "Abatzoglou2026Observed",
                kind: .citedBy
            ).absoluteString,
            "http://backend.example.com:8766/api/papers/Abatzoglou2026Observed/cited-by"
        )
        XCTAssertEqual(
            endpoints.libraryReferenceRetryURL(
                citekey: "Abatzoglou2026Observed"
            ).absoluteString,
            "http://backend.example.com:8766/api/papers/Abatzoglou2026Observed/references/retry"
        )
        XCTAssertEqual(
            endpoints.graphStatusURL.absoluteString,
            "http://backend.example.com:8766/api/graph/status"
        )
        XCTAssertEqual(
            endpoints.libraryAttachmentPlanURL(citekey: "Namias1966Nature").absoluteString,
            "http://backend.example.com:8766/api/papers/Namias1966Nature/attachment-plan"
        )
        XCTAssertEqual(
            endpoints.libraryAttachmentCommitURL(citekey: "Namias1966Nature").absoluteString,
            "http://backend.example.com:8766/api/papers/Namias1966Nature/attachment-commit"
        )
        XCTAssertEqual(
            endpoints.libraryPDFURL(citekey: "Namias1966Nature").absoluteString,
            "http://backend.example.com:8766/api/papers/Namias1966Nature/pdf"
        )
    }

    func testDetailCitekeyIsEncodedAsOnePathComponent() {
        let endpoints = GleanBackendEndpoints(
            intakeBase: URL(string: "http://127.0.0.1:8765")!,
            libraryBase: URL(string: "http://127.0.0.1:8766")!
        )

        XCTAssertEqual(
            endpoints.libraryDetailURL(citekey: "A B/C").absoluteString,
            "http://127.0.0.1:8766/api/papers/A%20B%2FC"
        )
        XCTAssertEqual(
            endpoints.libraryRelationURL(citekey: "A B/C", kind: .references)
                .absoluteString,
            "http://127.0.0.1:8766/api/papers/A%20B%2FC/references"
        )
    }
}
