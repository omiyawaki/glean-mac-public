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
        XCTAssertEqual(timeout, 660, accuracy: 0.001)
    }

    func testSubmitReviewAddSendsOperationIDHeader() async throws {
        let capture = RequestCapture()
        MockURLProtocol.requestHandler = { request in
            capture.path = request.url?.path
            capture.operationID = request.value(forHTTPHeaderField: "X-Glean-Operation-ID")
            capture.body = Self.bodyString(from: request)
            return Self.ok(request: request)
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
        XCTAssertTrue(capture.bodies[1].contains("%PDF-1.7"))
    }

    private static func ok(request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(#"{"ok":true}"#.utf8))
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
