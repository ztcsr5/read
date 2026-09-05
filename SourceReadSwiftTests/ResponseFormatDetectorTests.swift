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

    func testDetectsJSONPJavaScriptAssignmentAndHTMLEscapedPayloads() {
        let jsonp = "callback({\"data\":{\"value\":42}});"
        let assignment = "window.__BOOTSTRAP__ = [1, {\"ok\":true}];"
        let escaped = "{&quot;title&quot;:&quot;转义书&quot;,&quot;count&quot;:2}"

        let jsonpObject = ResponseFormatDetector.jsonObject(from: jsonp) as? [String: Any]
        let jsonpData = jsonpObject?["data"] as? [String: Any]
        XCTAssertEqual(jsonpData?["value"] as? Int, 42)
        XCTAssertEqual((ResponseFormatDetector.jsonObject(from: assignment) as? [Any])?.count, 2)
        XCTAssertEqual((ResponseFormatDetector.jsonObject(from: escaped) as? [String: Any])?["title"] as? String, "转义书")
    }

    func testDecodesNumericEntitiesAndPercentEncodedJSONEnvelope() {
        let numeric = "{&#34;title&#34;:&#34;A &#x4E66;&#34;}"
        let encodedEnvelope = "data=%7B%22title%22%3A%22Encoded%22%7D&ok=1"

        XCTAssertEqual((ResponseFormatDetector.jsonObject(from: numeric) as? [String: Any])?["title"] as? String, "A 书")
        XCTAssertEqual((ResponseFormatDetector.jsonObject(from: encodedEnvelope) as? [String: Any])?["title"] as? String, "Encoded")
    }
}
