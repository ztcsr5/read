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
          java.sha1('abc'),
          CryptoJS.SHA1('abc').toString(),
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
            "900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|a9993e364706816aba3e25717850c26c9cd0d89d|a9993e364706816aba3e25717850c26c9cd0d89d|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad|abc|abc|abc|abc|abc|abc"
        )
    }

    func testCryptoJSHmacAndEncoders() throws {
        let script = """
        [
          CryptoJS.HmacSHA256('abc', 'key').toString(),
          CryptoJS.enc.Hex.stringify(CryptoJS.enc.Utf8.parse('abc')),
          CryptoJS.enc.Utf8.stringify(CryptoJS.enc.Hex.parse('616263')),
          CryptoJS.enc.Base64.stringify(CryptoJS.enc.Utf8.parse('abc')),
          CryptoJS.enc.Utf8.stringify(CryptoJS.enc.Base64.parse('YWJj')),
          CryptoJS.SHA256(CryptoJS.enc.Utf8.parse('abc')).toString()
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(
            value,
            "9c196e32dc0175f86f4b1cb89289d6619de6bee699e4c378e68309ed97a1a6ab|616263|abc|YWJj|abc|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
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

    func testNativeGetStringListSupportsConnectorRules() throws {
        let html = """
        <html><body>
          <a class='free'>第一章</a>
          <a class='free'>第三章</a>
          <a class='vip'>第二章</a>
          <a class='vip'>第四章</a>
        </body></html>
        """
        let script = """
        [
          java.getStringList(html, '.missing || .free@text').join(','),
          java.getStringList(html, '.free%%.vip@text').join(',')
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["html": html, "baseUrl": "https://example.com"])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "第一章,第三章|第一章,第二章,第三章,第四章")
    }

    func testNativeGetStringListSupportsXPathRules() throws {
        let html = """
        <html><body>
          <div class='toc'>
            <a href='/1'>One</a>
            <a href='/2'>Two</a>
          </div>
        </body></html>
        """

        let result = JSCoreRuntime().evaluate(
            #"java.getStringList(html, '//div[@class="toc"]/a/@href').join(',')"#,
            variables: ["html": html, "baseUrl": "https://example.com/book"]
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "https://example.com/1,https://example.com/2")
    }

    func testNativeGetStringCanUseDefaultHtmlVariable() throws {
        let html = """
        <html><body>
          <h2>Title</h2>
          <a href="/1">One</a>
          <a href="/2">Two</a>
        </body></html>
        """
        let script = """
        java.getString('h2@text') + '|' + java.getStringList('a@href').join(',')
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["html": html, "baseUrl": "https://example.com"])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "Title|https://example.com/1,https://example.com/2")
    }

    func testNativeGetElementsUsesDefaultHtmlVariable() throws {
        let html = """
        <html><body>
          <div id="content">
            <p>A</p>
            <p>B</p>
          </div>
        </body></html>
        """

        let result = JSCoreRuntime().evaluate(
            "java.getElements('#content p').text() + '|' + java.getElements('#content p').eachText().join(',')",
            variables: ["html": html, "baseUrl": "https://example.com"]
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "A\nB|A,B")
    }

    func testNativeGetStringIgnoresBooleanFlagWhenUsingDefaultHtml() throws {
        let html = """
        <html><body>
          <h2>Title</h2>
          <a href="/1">One</a>
          <a href="/2">Two</a>
        </body></html>
        """
        let script = """
        java.getString('h2@text', true) + '|' + java.getStringList('a@text', false).join(',')
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["result": html, "baseUrl": "https://example.com"])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "Title|One,Two")
    }

    func testNativeStringListsSupportJavaListAliases() throws {
        let html = """
        <html><body>
          <a>One</a>
          <a>Two</a>
        </body></html>
        """
        let script = """
        var list = java.getStringList('a@text');
        var elements = java.getElements('a').eachText();
        list.get(1) + '|' + list.size() + '|' + list.isEmpty() + '|' + elements.get(0)
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["html": html])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "Two|2|false|One")
    }

    func testJavaStyleStringHelpersAreAvailable() throws {
        let script = """
        'abcdef'.contains('bcd') + '|' + 'abcdef'.startsWith('abc') + '|' + 'abcdef'.endsWith('def')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "true|true|true")
    }
}
