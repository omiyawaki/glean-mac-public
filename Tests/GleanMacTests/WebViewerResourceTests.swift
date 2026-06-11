import XCTest
@testable import GleanMac

final class WebViewerResourceTests: XCTestCase {
    func testDarkReaderScriptResourceIsLoadable() throws {
        let url = try XCTUnwrap(WebViewer.darkReaderScriptURL())
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("DarkReader"))
    }
}
