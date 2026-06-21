import XCTest
@testable import SourceReadSwift

final class JSCoreRuntimeTests: XCTestCase {
    func testNativeUrlEncodeBridge() throws {
        let result = JSCoreRuntime().evaluate("java.urlEncode('斗破苍穹&a=1')")
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(value.contains("%"))
        XCTAssertFalse(value.contains("&"))
    }

    func testNativeBase64Bridge() throws {
        let result = JSCoreRuntime().evaluate("java.base64Decode(java.base64Encode('abc'))")
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "abc")
    }

    func testCommonHashAndBase64Aliases() throws {
        let script = """
        [
          java.md5('abc'),
          java.hexMd5('abc'),
          java.md5Encode('abc'),
          md5('abc'),
          CryptoJS.MD5('abc').toString(),
          java.sha256('abc'),
          atob(btoa('abc')),
          java.decodeBase64(java.base64('abc')),
          java.base64DecodeToString(java.base64Encode('abc')),
          java.base64Decoder(java.base64Encode('abc')),
          java.unbase64(java.base64Encode('abc')),
          unbase64(java.base64Encode('abc'))
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(
            value,
            "900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad|abc|abc|abc|abc|abc|abc"
        )
    }

    func testURIEncodingAliases() throws {
        let script = """
        [
          java.encodeURI('a&b=1'),
          java.encodeURIComponent('a&b=1'),
          java.decodeURI('a%26b%3D1'),
          java.decodeURIComponent('a%26b%3D1')
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "a%26b%3D1|a%26b%3D1|a&b=1|a&b=1")
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
