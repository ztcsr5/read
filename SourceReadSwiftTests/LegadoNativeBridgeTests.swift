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

    func testNativeModelBridgesAreInjectedForJavaScriptRules() throws {
        let chapter = BookChapter(title: "VIP 1", url: "https://example.com/1", bookUrl: "https://example.com", index: 0, isVip: true)
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("chapter.title + '|' + chapter.isVip()", variables: ["chapter": chapter])
        guard case .success(let value) = result else { return XCTFail("expected success") }
        XCTAssertEqual(value, "VIP 1|true")
    }
}
