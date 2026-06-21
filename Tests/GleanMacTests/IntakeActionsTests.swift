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
            return Self.reviewOk(request: request)
        }

        try await IntakeActions.reviewAdd(doi: "10.1002/qj.70192")

        let timeout = try XCTUnwrap(capture.timeoutInterval)
        XCTAssertEqual(timeout, 660, accuracy: 0.001)
    }

    func testSubmitReviewAddSendsOperationIDHeader() async throws {
        let capture = RequestCapture()
        MockURLProtocol.requestHandler = { request in
            capture.path = request.url?.path
            capture.operationID = request.value(forHTTPHeaderField: "X-Glean-Operation-ID")
            capture.body = Self.bodyString(from: request)
            return Self.reviewOk(request: request)
        }
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let operation = PendingOperation(
            id: id,
            createdAt: Date(timeIntervalSince1970: 0),
            kind: .reviewAdd(doi: "10.1000/add"),
            status: .queued,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let result = try await IntakeActions.submit(operation)

        XCTAssertEqual(result, .synced)
        XCTAssertEqual(capture.path, "/api/review/add")
        XCTAssertEqual(capture.operationID, id.uuidString)
        XCTAssertEqual(capture.body, "doi=10.1000/add")
    }

    func testReviewSkipRejectsNonTerminalReviewStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(
                #"{"ok":true,"review_status":"not_found","removed_from_queue":false}"#.utf8
            )
            return (response, body)
        }

        do {
            try await IntakeActions.reviewSkip(doi: "10.1000/missing")
            XCTFail("Expected non-terminal review status to fail")
        } catch IntakeActions.ActionError.server(let message) {
            XCTAssertTrue(message.contains("not_found"))
        }
    }

    func testReviewSkipRejectsMissingTerminalReviewStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            Self.ok(request: request)
        }

        do {
            try await IntakeActions.reviewSkip(doi: "10.1000/missing-status")
            XCTFail("Expected missing review status to fail")
        } catch IntakeActions.ActionError.server(let message) {
            XCTAssertTrue(message.contains("Review action did not finish"))
        }
    }

    func testSubmitAttachUploadsStagedPDF() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("%PDF-1.7\nbody".utf8).write(to: source)
        let capture = RequestCapture()
        MockURLProtocol.requestHandler = { request in
            capture.path = request.url?.path
            capture.operationID = request.value(forHTTPHeaderField: "X-Glean-Operation-ID")
            capture.contentType = request.value(forHTTPHeaderField: "Content-Type")
            capture.body = Self.bodyString(from: request)
            return Self.ok(request: request)
        }
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let operation = PendingOperation(
            id: id,
            createdAt: Date(timeIntervalSince1970: 0),
            kind: .attachPDF(stagedFilePath: source.path, citekey: "Abdi2026Hrrrcast"),
            status: .queued,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let result = try await IntakeActions.submit(operation)

        XCTAssertEqual(result, .synced)
        XCTAssertEqual(capture.path, "/attach")
        XCTAssertEqual(capture.operationID, id.uuidString)
        XCTAssertTrue(capture.contentType?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(capture.body?.contains("Abdi2026Hrrrcast") == true)
        XCTAssertTrue(capture.body?.contains("%PDF-1.7") == true)
    }

    func testSubmitAttachFailureReturnsNeedsReview() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("%PDF-1.7\nbody".utf8).write(to: source)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(
                #"{"ok":false,"error":"attach_failed","detail":"not found: Wang2026Mechanisms"}"#.utf8
            )
            return (response, body)
        }
        let id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let operation = PendingOperation(
            id: id,
            createdAt: Date(timeIntervalSince1970: 0),
            kind: .attachPDF(stagedFilePath: source.path,
                             citekey: "Wang2026Mechanisms"),
            status: .queued,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let result = try await IntakeActions.submit(operation)

        XCTAssertEqual(result, .needsReview("not found: Wang2026Mechanisms"))
    }

    func testSubmitAddPaperWithStagedPDFAddsThenUploadsPDF() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("%PDF-1.7\n10.1000/add".utf8).write(to: source)
        let capture = RequestCapture()
        MockURLProtocol.requestHandler = { request in
            capture.paths.append(request.url?.path ?? "")
            capture.operationIDs.append(
                request.value(forHTTPHeaderField: "X-Glean-Operation-ID") ?? ""
            )
            capture.bodies.append(Self.bodyString(from: request) ?? "")
            if request.url?.path == "/api/review/add" {
                return Self.reviewOk(request: request)
            }
            return Self.ok(request: request)
        }
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let operation = PendingOperation(
            id: id,
            createdAt: Date(timeIntervalSince1970: 0),
            kind: .addPaper(input: "10.1000/add",
                            stagedPDFPath: source.path),
            status: .queued,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let result = try await IntakeActions.submit(operation)

        XCTAssertEqual(result, .synced)
        XCTAssertEqual(capture.paths, ["/api/review/add", "/attach"])
        XCTAssertEqual(capture.operationIDs, [id.uuidString, id.uuidString])
        XCTAssertTrue(capture.bodies[0].contains("doi=10.1000/add"))
        XCTAssertTrue(capture.bodies[0].contains("source=add-paper"))
        XCTAssertTrue(capture.bodies[1].contains("%PDF-1.7"))
    }

    func testSubmitAddPaperDoesNotRequireReviewQueueTerminalStatus() async throws {
        let capture = RequestCapture()
        MockURLProtocol.requestHandler = { request in
            capture.path = request.url?.path
            capture.body = Self.bodyString(from: request)
            return Self.ok(request: request)
        }
        let id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let operation = PendingOperation(
            id: id,
            createdAt: Date(timeIntervalSince1970: 0),
            kind: .addPaper(input: "10.1000/direct", stagedPDFPath: nil),
            status: .queued,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let result = try await IntakeActions.submit(operation)

        XCTAssertEqual(result, .synced)
        XCTAssertEqual(capture.path, "/api/review/add")
        XCTAssertTrue(capture.body?.contains("source=add-paper") == true)
    }

    private static func ok(request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(#"{"ok":true}"#.utf8))
    }

    private static func reviewOk(request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (
            response,
            Data(#"{"ok":true,"review_status":"removed","removed_from_queue":true}"#.utf8)
        )
    }

    private static func bodyString(from request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8)
    }
}

private final class RequestCapture {
    nonisolated(unsafe) var timeoutInterval: TimeInterval?
    nonisolated(unsafe) var path: String?
    nonisolated(unsafe) var operationID: String?
    nonisolated(unsafe) var contentType: String?
    nonisolated(unsafe) var body: String?
    nonisolated(unsafe) var paths: [String] = []
    nonisolated(unsafe) var operationIDs: [String] = []
    nonisolated(unsafe) var bodies: [String] = []
}
