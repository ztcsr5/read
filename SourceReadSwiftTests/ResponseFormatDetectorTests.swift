import XCTest
@testable import SourceReadSwift

final class ResponseFormatDetectorTests: XCTestCase {
    func testRemovesUTF8BOMAndDetectsJSONWithHTMLContentType() {
        let body = "\u{FEFF}{\"data\":[{\"name\":\"Reader\"}]}"

        XCTAssertEqual(ResponseFormatDetector.normalizedBody(body), "{\"data\":[{\"name\":\"Reader\"}]}")
        XCTAssertTrue(ResponseFormatDetector.prefersJSON(body: body, headers: ["Content-Type": "text/html; charset=utf-8"]))
        XCTAssertNotNil(ResponseFormatDetector.jsonObject(from: body) as? [String: Any])
    }

    func testDetectsXSSIProtectedJSONWithOrWithoutNewline() {
        let withNewline = ")]}',\n{\"ok\":true}"
        let withoutNewline = ")]}'{\"ok\":true}"

        for body in [withNewline, withoutNewline] {
            XCTAssertTrue(ResponseFormatDetector.prefersJSON(body: body, headers: [:]))
            let object = ResponseFormatDetector.jsonObject(from: body) as? [String: Any]
            XCTAssertEqual(object?["ok"] as? Bool, true)
        }
    }

    func testDetectsPreWrappedAndEmbeddedBalancedJSON() {
        let pre = "<pre class=\"json\">{\"chapters\":[{\"title\":\"第一章\"}]}</pre>"
        let embedded = "<html><body>payload {\"nested\":{\"value\":\"ok\"},\"text\":\"} not a close\"} tail</body></html>"

        XCTAssertTrue(ResponseFormatDetector.prefersJSON(body: pre, headers: ["Content-Type": "text/plain"]))
        XCTAssertNotNil(ResponseFormatDetector.jsonObject(from: pre))
        let object = ResponseFormatDetector.jsonObject(from: embedded) as? [String: Any]
        let nested = object?["nested"] as? [String: Any]
        XCTAssertEqual(nested?["value"] as? String, "ok")
    }

    func testDoesNotClassifyOrdinaryHTMLOrMismatchedJSONAsJSON() {
        let html = "<html><body><div class=\"book\">No JSON here</div></body></html>"
        let malformed = "{\"data\":[1,2}"

        XCTAssertFalse(ResponseFormatDetector.prefersJSON(body: html, headers: ["Content-Type": "text/html"]))
        XCTAssertNil(ResponseFormatDetector.jsonObject(from: html))
        XCTAssertFalse(ResponseFormatDetector.prefersJSON(body: malformed, headers: ["Content-Type": "application/json"]))
        XCTAssertNil(ResponseFormatDetector.jsonObject(from: malformed))
    }
}
