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
    }
}
