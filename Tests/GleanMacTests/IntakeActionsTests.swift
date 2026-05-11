import XCTest
@testable import GleanMac

final class IntakeActionsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testReviewAddUsesLongWorkerTimeout() async throws {
        let capture = RequestCapture()
        MockURLProtocol.requestHandler = { request in
            capture.timeoutInterval = request.timeoutInterval
            return Self.ok(request: request)
        }

        try await IntakeActions.reviewAdd(doi: "10.1002/qj.70192")

        let timeout = try XCTUnwrap(capture.timeoutInterval)
        XCTAssertEqual(timeout, 150, accuracy: 0.001)
    }

    private static func ok(request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(#"{"ok":true}"#.utf8))
    }
}

private final class RequestCapture {
    nonisolated(unsafe) var timeoutInterval: TimeInterval?
}
