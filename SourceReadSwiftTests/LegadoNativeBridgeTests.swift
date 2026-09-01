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

    func testNativeModelBridgesAreInjectedForJavaScriptRules() throws {
        let chapter = BookChapter(title: "VIP 1", url: "https://example.com/1", bookUrl: "https://example.com", index: 0, isVip: true)
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("chapter.title + '|' + chapter.isVip()", variables: ["chapter": chapter])
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "VIP 1|true")
    }
}
