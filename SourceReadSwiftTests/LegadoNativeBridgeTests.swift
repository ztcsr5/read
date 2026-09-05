import XCTest
@testable import SourceReadSwift

final class LegadoNativeBridgeTests: XCTestCase {
    func testExecutionContextSharesPersistentValuesWithJavaBridge() throws {
        let executionContext = RuleExecutionContext()
        let runtime = JSCoreRuntime(executionContext: executionContext)

        let result = runtime.evaluate(
            "java.put('token', { value: 'abc' }); java.getVar('token');"
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, #"{"value":"abc"}"#)
        XCTAssertEqual(executionContext.get("token"), #"{"value":"abc"}"#)
    }

    func testSetContentWritesBackToExecutionContextAndNativeRuleResolver() throws {
        let executionContext = RuleExecutionContext(initialValues: [
            "result": "<p>Old</p>",
            "baseUrl": "https://example.com/book/"
        ])
        let runtime = JSCoreRuntime(executionContext: executionContext)

        let result = runtime.evaluate(
            "java.setContent('<div><a href=\"chapter-1\">New</a></div>'); ruleResolver.getElement('a').attr('href');"
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "https://example.com/book/chapter-1")
        XCTAssertEqual(executionContext.string(for: "result"), "<div><a href=\"chapter-1\">New</a></div>")
    }

    func testNativeJsoupObjectsPreserveDOMIdentityAndMutation() throws {
        let html = """
        <html><body>
          <div id="content">
            <p class="remove">Header</p>
            <a href="/1"><span>One</span></a>
            <a href="/2"><span>Two</span></a>
          </div>
        </body></html>
        """
        let runtime = JSCoreRuntime()

        let result = runtime.evaluate(
            """
            var doc = org.jsoup.Jsoup.parse(html, baseUrl);
            var removed = doc.select('.remove').first();
            removed.remove();
            var links = doc.select('#content a');
            [
              doc.select('.remove').size(),
              links.size(),
              links.eq(-1).text(),
              links.first().attr('href'),
              links.first().parent().attr('id')
            ].join('|');
            """,
            variables: ["html": html, "baseUrl": "https://example.com/book/"]
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "0|2|Two|https://example.com/1|content")
    }

    func testAjaxAllUsesNativeExecutionContextNetworkHandler() throws {
        let executionContext = RuleExecutionContext(networkHandler: { "loaded:\($0)" })
        let runtime = JSCoreRuntime(executionContext: executionContext)

        let result = runtime.evaluate(
            "java.ajaxAll(['https://example.com/1', 'https://example.com/2']).map(function(it) { return it.body(); }).join('|')"
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "loaded:https://example.com/1|loaded:https://example.com/2")
    }

    func testAjaxResponsePreservesStatusHeadersAndFinalURL() throws {
        let context = RuleExecutionContext(responseHandler: { _ in
            SourceResponse(
                url: URL(string: "https://example.com/final")!,
                statusCode: 206,
                headers: ["Content-Type": "text/plain", "X-Trace": "fixture"],
                body: "partial",
                data: Data("partial".utf8)
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("var r = java.ajax('https://example.com/start'); [r.statusCode, r.body(), r.url(), r.header('x-trace'), r.header('CONTENT-TYPE')].join('|')")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "206|partial|https://example.com/final|fixture|text/plain")
    }

    func testAjaxAllAndPostPreserveResponseMetadata() throws {
        let context = RuleExecutionContext(responseHandler: { encoded in
            SourceResponse(
                url: URL(string: encoded.contains("post") ? "https://example.com/post-final" : "https://example.com/get-final")!,
                statusCode: encoded.contains("post") ? 201 : 203,
                headers: ["X-Mode": encoded.contains("post") ? "post" : "get"],
                body: encoded.contains("post") ? "created" : "fetched",
                data: Data()
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("[java.ajaxAll(['https://example.com/get']).first().statusCode, java.ajaxAll(['https://example.com/get']).first().header('x-mode'), java.post('https://example.com/post', 'a=1').statusCode, java.post('https://example.com/post', 'a=1').body()].join('|')")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "203|get|201|created")
    }

    func testExplicitHtmlOverloadsForElementsAndParents() throws {
        let html = "<div class='wrap'><a>One</a><a>Two</a></div>"
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("java.getElements(html, 'a').eachText().join(',') + '|' + java.getParents(html, 'a').size() + '|' + java.removeElements(html, 'a').contains('One')", variables: ["html": html])
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "One,Two|6|false")
    }

    func testNativeCookieAndLogBridgesAreObservable() throws {
        let executionContext = RuleExecutionContext()
        let runtime = JSCoreRuntime(executionContext: executionContext)

        let result = runtime.evaluate(
            "cookie.setCookie('sid=1'); java.log('bridge-ready'); java.getCookie();"
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "sid=1")
        XCTAssertEqual(executionContext.string(for: "cookieHeader"), "sid=1")
        XCTAssertEqual(executionContext.logs(), ["bridge-ready"])
    }

    func testMissingNetworkHandlerProducesStructuredBridgeDiagnostic() throws {
        let executionContext = RuleExecutionContext()
        let runtime = JSCoreRuntime(executionContext: executionContext)

        let result = runtime.evaluate("java.ajax('https://fixture.local/missing').body()")
        guard case .success(let value) = result else {
            return XCTFail("missing handler should return an empty compatibility response")
        }
        XCTAssertEqual(value, "")
        XCTAssertTrue(executionContext.logs().contains { $0.contains("bridge.error java.ajax") })
    }

    func testLegadoRuleAnalyzerRoutesHTMLAndJSONThroughOneContext() throws {
        let analyzer = LegadoRuleAnalyzer()
        let html = "<div class='item'><a href='/a'>Alpha</a></div><div class='item'><a href='/b'>Beta</a></div>"
        XCTAssertEqual(
            analyzer.stringList(content: html, rule: ".item a@text", baseURL: URL(string: "https://example.com/") ),
            ["Alpha", "Beta"]
        )
        let json = #"{"items":[{"title":"One"},{"title":"Two"}]}"#
        XCTAssertEqual(analyzer.stringList(content: json, rule: "$.items[*].title", baseURL: nil), ["One", "Two"])
        XCTAssertEqual(analyzer.executionContext.string(for: "result"), json)
    }

    func testNativeJavaABIExposesFilesystemAndCryptoMethods() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("[typeof java.aesEncodeToString, typeof java.readTxtFile, typeof java.getZipStringContent, typeof java.downloadFile, typeof java.utf8ToGbk].join('|')")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "function|function|function|function|function")
    }

    func testLegacyVariableAliasesRemainAvailable() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("java.putVar('x', 'v'); var a = java.getValue('x'); java.removeVar('x'); a + '|' + java.getVar('x')")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "v|")
    }

    func testNativeJsoupAndResponseCompatibilitySurface() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            var d = org.jsoup.Jsoup.parse('<div id=\"x\"><a href=\"/a\">A</a></div>', 'https://example.com/');
            var n = d.select('a').first();
            [typeof n.nodeName, typeof n.getAttributes, typeof n.absUrl, typeof n.parent,
             typeof n.nextSibling, typeof d.title, typeof java.ajax].join('|');
        """)
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "function|function|function|function|function|function|function")
    }

    func testJsoupElementAbiSiblingAndIndexHelpers() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("var d=org.jsoup.Jsoup.parse('<div><p>A</p><p>B</p><p>C</p></div>'); var p=d.select('p').get(1); [p.firstElementSibling().text(), p.lastElementSibling().text(), d.getElementsByIndexLessThan(2).size(), d.getElementsByIndexEquals(2).text()].join('|')")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "A|C|2|C")
    }

    func testJavaUtilityCollectionsAndStringBuilder() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("var b=new Packages.java.lang.StringBuilder('A'); b.append('B').append(3); var m=new Packages.java.util.HashMap(); m.put('k','v'); [b.toString(),m.get('k'),m.containsKey('k'),Packages.java.lang.Integer.parseInt('42')].join('|')")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "AB3|v|true|42")
    }

    func testJXNodeHybridValueBridge() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("var n = new JXNode(42); [n.isNumber(), n.asDouble(), n.toString(), n.isString()].join('|')")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "true|42|42|false")
    }

    func testJXNodeSelectsNativeElement() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("var d=org.jsoup.Jsoup.parse('<div><a>A</a><a>B</a></div>'); var n=new JXNode(d); n.selOne('a').text()")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "A")
    }



    func testExpandedJavaCompatibilitySurface() throws {
        let context = RuleExecutionContext(responseHandler: { encoded in
            let isHead = encoded.contains("HEAD")
            let body = isHead ? "" : "abc"
            return SourceResponse(
                url: URL(string: "https://example.com/final")!,
                statusCode: isHead ? 204 : 200,
                headers: ["X-Test": "ok"],
                body: body,
                data: Data(body.utf8)
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("""
            java.cacheFile('compat.txt', 'cached');
            var before = String.fromCharCode.apply(null, java.readFile('compat.txt'));
            var removed = java.deleteFile('compat.txt');
            var after = java.readTxtFile('compat.txt');
            var head = java.head('https://example.com/head', {'X-Head':'1'});
            [before, removed, after, java.digestHex('abc','SHA-256'), java.HMacHex('abc','HmacSHA1','key'), head.statusCode, head.header('x-test'), java.ajaxBytes('https://example.com/a').length].join('|');
        """)
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "cached|true||ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad|4fd0b215276ef12f2b3e4c8ecac2811498b656fc|204|ok|3")
    }

    func testImportScriptExecutesDataURLScript() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("java.importScript('data:text/javascript,function imported(){return \"ok\";}'); imported();")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "ok")
    }

    func testNativeModelBridgesAreInjectedForJavaScriptRules() throws {
        let chapter = BookChapter(title: "VIP 1", url: "https://example.com/1", bookUrl: "https://example.com", index: 0, isVip: true)
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("chapter.title + '|' + chapter.isVip()", variables: ["chapter": chapter])
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "VIP 1|true")
    }

    func testFlutterLegadoUtilityAliasesAndJavaPackages() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            var bytes = java.strToBytes('abc');
            var b64 = java.base64Encode(bytes);
            var url = new Packages.java.net.URL('https://example.com/a?q=1');
            var digest = Packages.java.security.MessageDigest.getInstance('SHA-256').digest(bytes);
            var key = new Packages.javax.crypto.spec.SecretKeySpec(java.strToBytes('key'), 'HmacSHA1');
            var mac = Packages.javax.crypto.Mac.getInstance('HmacSHA1'); mac.init(key);
            [java.bytesToStr(java.base64DecodeToByteArray(b64)), b64, url.getHost(), url.getPath(), url.getQuery(), digest.length, mac.doFinal(bytes).length].join('|');
        """)
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "abc|YWJj|example.com|/a|q=1|32|20")
    }

    func testJavaCryptoBridgesPreserveNonASCIIBytesAndRelativeURLs() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            var bytes = java.strToBytes('你好');
            var digest = Packages.java.security.MessageDigest.getInstance('SHA-256').digest(bytes);
            var key = new Packages.javax.crypto.spec.SecretKeySpec(java.strToBytes('密钥'), 'HmacSHA1');
            var mac = Packages.javax.crypto.Mac.getInstance('HmacSHA1'); mac.init(key);
            var relative = new Packages.java.net.URL('../chapter-2', 'https://example.com/books/1/');
            [digest.length, mac.doFinal(bytes).length, relative.toString(), relative.getPath()].join('|');
        """)
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "32|20|https://example.com/books/chapter-2|/books/chapter-2")
    }

    func testJavaStringCharsetAwareGetBytesAndConstructor() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            var utf16 = 'A'.getBytes('UTF-16LE');
            var restored = new Packages.java.lang.String(utf16, 'UTF-16LE');
            restored.toString() + '|' + utf16.length + '|' + java.bytesToStr(java.strToBytes('A'));
        """)
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "A|2|A")
    }

    func testPostFormUsesFormEncodingAndHeaderBridge() throws {
        var requests: [String] = []
        let context = RuleExecutionContext(responseHandler: { encoded in
            requests.append(encoded)
            return SourceResponse(
                url: URL(string: "https://example.com/form")!,
                statusCode: 201,
                headers: [:],
                body: "created",
                data: Data("created".utf8)
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("java.postForm('https://example.com/form', 'a=1&q=hello%20world').statusCode + '|' + java.postForm('https://example.com/form', 'a=1').body()")
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "201|created")
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].contains("@Body:a%3D1%26q%3Dhello%20world") || requests[0].contains("@Body:a=1&q=hello world"))
        XCTAssertTrue(requests.allSatisfy { $0.localizedCaseInsensitiveContains("Content-Type") })
    }

    func testGetStrGetJsonAndGetStringDefaultSemantics() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            java.put('cache-key', 'cached');
            var json = java.getJson('{"title":"One"}');
            [java.getStr('cache-key', 'fallback'), java.getStr('missing', 'fallback'), json.title, java.getString('missing', 'default')].join('|');
        """)
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "cached|fallback|One|default")
    }

    func testSourceBookChapterGetterAliasesSurviveVariableInjection() throws {
        let source = BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://example.com/source", searchUrl: "https://example.com")
        let book = SearchBook(name: "Book", author: "Author", coverUrl: nil, bookUrl: "https://example.com/book", sourceName: "Fixture", sourceUrl: source.bookSourceUrl, intro: nil)
        let chapter = BookChapter(title: "Chapter 1", url: "https://example.com/chapter", bookUrl: book.bookUrl, index: 4, isVip: false)
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("[source.getName(), source.getUrl(), book.getName(), book.getAuthor(), book.getTocUrl(), chapter.getName(), chapter.getIndex()].join('|')", variables: ["source": source, "book": book, "chapter": chapter])
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "Fixture|https://example.com/source|Book|Author|https://example.com/book|Chapter 1|4")
    }

}
