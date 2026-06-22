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

    func testNativeElementsSupportIndexedAccess() throws {
        let html = """
        <html><body>
          <a href="/1"><span>One</span></a>
          <a href="/2"><span>Two</span></a>
          <a href="/3"></a>
        </body></html>
        """
        let script = """
        var links = java.getElements('a');
        var parsed = Packages.org.jsoup.Jsoup.parse(html).select('a');
        [
          links.get(1).text(),
          links.get(1).attr('href'),
          links.first().text(),
          links.size(),
          links.isEmpty(),
          parsed.get(0).text(),
          links.get(1).select('span').text()
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["html": html, "baseUrl": "https://example.com"])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "Two|https://example.com/2|One|3|false|One|Two")
    }

    func testJavaStyleStringHelpersAreAvailable() throws {
        let script = """
        [
          'abcdef'.contains('bcd'),
          'abcdef'.startsWith('abc'),
          'abcdef'.endsWith('def'),
          'Title'.equals('Title'),
          'Title'.equalsIgnoreCase('title'),
          'a-b-c'.replaceAll('-', '')
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "true|true|true|true|true|abc")
    }

    func testCommonLegadoJavaHelpersAreAvailable() throws {
        let html = """
        <html><body>
          <span class="count">42</span>
          <span class="score">3.5</span>
        </body></html>
        """
        let script = """
        java.put('stored.count', '7');
        source.setVariable('token', 'abc');
        book.setVariable('chapter', '12');
        cookie.setCookie('sid=ok; theme=dark');
        [
          java.getInt('.count@text', 0),
          java.getDouble('.score@text', 0),
          java.getInt('stored.count', 0),
          source.getVariable('token'),
          book.getVariable('chapter'),
          chapter.isVip(),
          cookie.getKey('', 'sid'),
          java.getCookie(),
          java.getWebViewUA().contains('SourceReadSwift'),
          java.toast('x'),
          Packages.android.text.TextUtils.isEmpty(''),
          java.util.UUID.randomUUID().length > 20,
          'ABC'.getBytes().join(','),
          Packages.java.util.Base64.encodeToString('ABC'.getBytes()),
          JavaImporter().String('ok').toString(),
          importPackage(Packages.java.util) === Packages.java.util
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(
            script,
            variables: ["html": html, "chapter": ["title": "VIP章节"]]
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "42|3.5|7|abc|12|true|ok|sid=ok; theme=dark|true||true|true|65,66,67|QUJD|ok|true")
    }

    func testConnectChainSupportsCookiesBodyAndExecuteAliases() throws {
        let runtime = JSCoreRuntime { request in
            request
        }
        let script = """
        [
          java.connect('https://example.com/a').cookie('sid=1').get().body(),
          java.connect('https://example.com/b').headers({'X-Test':'1'}).post('q=1').text(),
          java.connect('https://example.com/c').data('k', 'v').execute().toString(),
          java.fetch('https://example.com/d', {'X-Fetch':'1'}).body()
        ].join('\\n---\\n')
        """

        let result = runtime.evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(value.contains("https://example.com/a@Header:{\"Cookie\":\"sid=1\"}"))
        XCTAssertTrue(value.contains("https://example.com/b@Header:{\"X-Test\":\"1\"}@Body:q=1"))
        XCTAssertTrue(value.contains("https://example.com/c@Body:k=v"))
        XCTAssertTrue(value.contains("https://example.com/d@Header:{\"X-Fetch\":\"1\"}"))
    }

    func testChapterIsVipAvoidsDictionaryOverride() throws {
        // 验证传入外部 chapter 覆盖后，isVip() 方法依然可用
        let script = "chapter.isVip()"
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate(script, variables: ["chapter": ["title": "第123章 VIP订阅付费"]])
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "true")
    }

    func testJsoupSelectionCascadingDOMAPIs() throws {
        let html = """
        <html><body>
          <div id="content">
            <p class="remove-me">Header</p>
            <div class="chapters">
              <a href="/c/1"><span>One</span></a>
              <a href="/c/2"><span>Two</span></a>
              <a href="/c/3"><span>Three</span></a>
            </div>
          </div>
        </body></html>
        """
        let script = """
        var doc = org.jsoup.Jsoup.parse(html, 'https://example.com');
        // 测试 remove
        doc.select('.remove-me').remove();
        // 测试 eq 级联和 outerHtml/text
        var firstLinkText = doc.select('.chapters a').eq(1).select('span').text();
        var outer = doc.select('.chapters a').eq(2).outerHtml();
        // 测试 children
        var childCount = doc.select('.chapters').children().size();
        // 测试 parents
        var parentHtml = doc.select('.chapters span').eq(0).parents().html();
        
        [
          doc.select('.remove-me').size(), // 应该为 0
          firstLinkText, // 应该为 "Two"
          outer.contains('Three'), // 应该为 true
          childCount, // 应该为 3
          parentHtml.contains('id="content"') // 应该为 true
        ].join('|')
        """
        
        let result = JSCoreRuntime().evaluate(script, variables: ["html": html])
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "0|Two|true|3|true")
    }
}
