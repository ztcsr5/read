import XCTest
@testable import SourceReadSwift

final class JSCoreRuntimeTests: XCTestCase {
    func testNativeUrlEncodeBridge() throws {
        let result = JSCoreRuntime().evaluate("java.urlEncode('斗破苍穹')")
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(value.contains("%"))
    }

    func testNativeBase64Bridge() throws {
        let result = JSCoreRuntime().evaluate("java.base64Decode(java.base64Encode('abc'))")
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "abc")
    }

    func testNativeGetStringBridge() throws {
        let html = "<html><body><div class='book'><a href='/b/1'>斗破苍穹</a></div></body></html>"
        let script = "java.getString(html, '.book a@text')"
        let result = JSCoreRuntime().evaluate(script, variables: ["html": html, "baseUrl": "https://example.com"])
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "斗破苍穹")
    }

    func testJsoupParseSelectionUsesSwiftSoupBridge() throws {
        let title = "\u{6597}\u{7834}\u{82cd}\u{7a79}"
        let html = "<html><body><div class='book'><a href='/b/1'>\(title)</a></div></body></html>"
        let script = "org.jsoup.Jsoup.parse(html).select('.book a').attr('href') + '|' + Packages.org.jsoup.Jsoup.parse(html).select('.book a').text()"
        let result = JSCoreRuntime().evaluate(script, variables: ["html": html])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "/b/1|\(title)")
    }

    func testNativeGetStringSupportsEnhancedHtmlRules() throws {
        let html = """
        <html><body>
          <a class='chapter' href='/c/1'>One</a>
          <a class='chapter' href='/c/2'>Two</a>
          <div class='intro'>Outer <span>Inner</span> Tail</div>
        </body></html>
        """

        let indexed = JSCoreRuntime().evaluate(
            "java.getString(html, '.chapter@1@href')",
            variables: ["html": html, "baseUrl": "https://example.com"]
        )
        let ownText = JSCoreRuntime().evaluate(
            "java.getString(html, '.intro@ownText')",
            variables: ["html": html, "baseUrl": "https://example.com"]
        )

        guard case .success(let indexedValue) = indexed,
              case .success(let ownTextValue) = ownText else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(indexedValue, "https://example.com/c/2")
        XCTAssertEqual(ownTextValue, "Outer Tail")
    }
}
