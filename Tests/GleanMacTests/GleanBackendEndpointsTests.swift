import XCTest
@testable import GleanMac

final class GleanBackendEndpointsTests: XCTestCase {
    func testEndpointsDeriveEveryBackendRoute() {
        let endpoints = GleanBackendEndpoints(
            intakeBase: URL(string: "http://backend.example.com:8765")!,
            libraryBase: URL(string: "http://backend.example.com:8766")!
        )

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

    func testDefaultsToLocalhostWhenUnconfigured() {
        let defaults = UserDefaults(suiteName: "GleanBackendEndpointsTests.empty")!
        defaults.removePersistentDomain(forName: "GleanBackendEndpointsTests.empty")
        let endpoints = GleanBackendEndpoints.resolve(environment: [:], defaults: defaults)

        XCTAssertEqual(endpoints.intakeBase.absoluteString, "http://localhost:8765")
        XCTAssertEqual(endpoints.libraryBase.absoluteString, "http://localhost:8766")
    }

    func testEnvironmentOverridesDefaultsAndIgnoresInvalidValues() {
        let suite = "GleanBackendEndpointsTests.override"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("http://stored.example.com:1", forKey: "GleanIntakeURL")
        defaults.set("http://stored.example.com:2", forKey: "GleanLibraryURL")

        let endpoints = GleanBackendEndpoints.resolve(
            environment: [
                "GLEAN_INTAKE_URL": "http://env.example.com:9",
                "GLEAN_LIBRARY_URL": "not a url"
            ],
            defaults: defaults
        )

        XCTAssertEqual(endpoints.intakeBase.absoluteString, "http://env.example.com:9")
        XCTAssertEqual(endpoints.libraryBase.absoluteString, "http://stored.example.com:2")
    }
}
