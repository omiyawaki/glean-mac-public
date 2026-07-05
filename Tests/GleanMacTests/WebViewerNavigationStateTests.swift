import XCTest
@testable import GleanMac

final class WebViewerNavigationStateTests: XCTestCase {
    func testInitialRequestedURLStartsNavigation() {
        var state = WebViewerNavigationState()
        let doiURL = URL(string: "https://doi.org/10.1000/example")!

        XCTAssertTrue(state.shouldLoad(requestedURL: doiURL))
    }

    func testRepeatedSwiftUIUpdateForSameRequestedURLDoesNotReloadRedirectedPage() {
        var state = WebViewerNavigationState()
        let doiURL = URL(string: "https://doi.org/10.1000/example")!

        XCTAssertTrue(state.shouldLoad(requestedURL: doiURL))

        XCTAssertFalse(state.shouldLoad(requestedURL: doiURL))
    }

    func testChangedRequestedURLStartsNavigation() {
        var state = WebViewerNavigationState()
        let firstURL = URL(string: "https://doi.org/10.1000/first")!
        let secondURL = URL(string: "https://doi.org/10.1000/second")!

        XCTAssertTrue(state.shouldLoad(requestedURL: firstURL))

        XCTAssertTrue(state.shouldLoad(requestedURL: secondURL))
    }
}
