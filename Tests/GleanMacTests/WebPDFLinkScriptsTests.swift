import JavaScriptCore
import XCTest
@testable import GleanMac

final class WebPDFLinkScriptsTests: XCTestCase {
    func testClickScriptIgnoresInvisiblePDFReferenceLink() throws {
        let result = try evaluatePDFClickScript(elements: [
            [
                "text": "https://www.ipcc.ch/site/assets/uploads/sites/2/2019/06/SR15_Full_Report_High_Res.pdf",
                "href": "https://www.ipcc.ch/site/assets/uploads/sites/2/2019/06/SR15_Full_Report_High_Res.pdf",
                "visible": false
            ]
        ])

        XCTAssertEqual(result.clicked, false)
        XCTAssertEqual(result.reason, "no PDF candidates")
        XCTAssertEqual(result.clickedHrefs, [])
    }

    func testClickScriptIgnoresLowConfidenceVisiblePDFReferenceURL() throws {
        let result = try evaluatePDFClickScript(elements: [
            [
                "text": "https://www.ipcc.ch/site/assets/uploads/sites/2/2019/06/SR15_Full_Report_High_Res.pdf",
                "href": "https://www.ipcc.ch/site/assets/uploads/sites/2/2019/06/SR15_Full_Report_High_Res.pdf",
                "visible": true
            ]
        ])

        XCTAssertEqual(result.clicked, false)
        XCTAssertEqual(result.reason, "no PDF candidates")
        XCTAssertEqual(result.clickedHrefs, [])
    }

    func testClickScriptClicksVisibleDownloadPDFCandidate() throws {
        let result = try evaluatePDFClickScript(elements: [
            [
                "text": "Download PDF",
                "href": "https://example.com/article.pdf",
                "visible": true
            ]
        ])

        XCTAssertEqual(result.clicked, true)
        XCTAssertEqual(result.href, "https://example.com/article.pdf")
        XCTAssertEqual(result.clickedHrefs, ["https://example.com/article.pdf"])
    }

    private struct PDFClickResult {
        let clicked: Bool
        let reason: String?
        let href: String?
        let clickedHrefs: [String]
    }

    private func evaluatePDFClickScript(
        elements: [[String: Any]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> PDFClickResult {
        let context = try XCTUnwrap(JSContext(), file: file, line: line)
        let elementsJSON = try String(data: JSONSerialization.data(withJSONObject: elements),
                                      encoding: .utf8).unwrap()

        context.evaluateScript("""
        var clickedHrefs = [];
        var rawElements = \(elementsJSON);
        var elements = rawElements.map(function(config) {
          return {
            tagName: config.tagName || "A",
            innerText: config.text || "",
            textContent: config.text || "",
            href: config.href || "",
            offsetWidth: config.visible ? 10 : 0,
            offsetHeight: config.visible ? 10 : 0,
            getClientRects: function() {
              return { length: config.visible ? 1 : 0 };
            },
            getAttribute: function(name) {
              return (config.attributes && config.attributes[name]) || "";
            },
            removeAttribute: function(name) {
              this.removedAttribute = name;
            },
            scrollIntoView: function() {
              this.scrolled = true;
            },
            click: function() {
              this.clicked = true;
              clickedHrefs.push(this.href);
            }
          };
        });
        var document = {
          querySelectorAll: function(_) { return elements; }
        };
        """)

        let rawResult = try XCTUnwrap(
            context.evaluateScript(WebPDFLinkScripts.pdfClickScript).toString(),
            file: file,
            line: line
        )
        let data = try XCTUnwrap(rawResult.data(using: .utf8), file: file, line: line)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            file: file,
            line: line
        )
        let clickedHrefs = context
            .objectForKeyedSubscript("clickedHrefs")?
            .toArray() as? [String] ?? []

        return PDFClickResult(
            clicked: object["clicked"] as? Bool ?? false,
            reason: object["reason"] as? String,
            href: object["href"] as? String,
            clickedHrefs: clickedHrefs
        )
    }
}

private extension Optional where Wrapped == String {
    func unwrap(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try XCTUnwrap(self, file: file, line: line)
    }
}
