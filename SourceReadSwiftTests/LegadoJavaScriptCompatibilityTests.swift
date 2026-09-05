import Foundation
import XCTest
@testable import SourceReadSwift

/// Stage 17 coverage for the async/Promise syntax used by Android Legado
/// sources.  JavaScriptCore executes the bridge synchronously, so every test
/// intentionally unwraps the synchronous facade with `valueOf()`/`toString()`
/// instead of waiting on a real event loop.
final class LegadoJavaScriptCompatibilityTests: XCTestCase {
    func testNormalizationStripsAwaitAndAsyncOutsideLiterals() {
        let source = #"""
            // await in a comment
            var text = "await async Promise";
            var pattern = /await\s+async/;
            async function load(value) { return await Promise.resolve(value); }
            var arrow = async (value) => await Promise.resolve(value);
            load(text)
            """#

        let normalized = LegadoJavaScriptCompatibility.normalize(source)

        XCTAssertTrue(normalized.changed)
        XCTAssertFalse(normalized.normalizedScript.contains("async function"))
        XCTAssertFalse(normalized.normalizedScript.contains("return await"))
        XCTAssertTrue(normalized.normalizedScript.contains("\"await async Promise\""))
        XCTAssertTrue(normalized.normalizedScript.contains("/await\\s+async/"))
        XCTAssertTrue(normalized.features.contains("await"))
        XCTAssertTrue(normalized.features.contains("async"))
        XCTAssertTrue(normalized.features.contains("promise"))
    }

    func testAtJsAndJsWrappersAreRemoved() {
        XCTAssertEqual(
            LegadoJavaScriptCompatibility.normalize("  @js: await Promise.resolve('ok')  ").originalScript,
            "await Promise.resolve('ok')"
        )
        XCTAssertEqual(
            LegadoJavaScriptCompatibility.normalize("<js>await Promise.resolve('ok')</js>").normalizedScript
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "Promise.resolve('ok')"
        )
    }

    func testAwaitJavaAjaxAndThenableResponse() throws {
        let runtime = fixtureRuntime { request in
            XCTAssertEqual(request, "https://fixture.local/ajax")
            return self.response(body: "ajax-body", url: "https://fixture.local/ajax", headers: ["X-Test": "ajax"])
        }

        let result = runtime.evaluate("await java.ajax('https://fixture.local/ajax').then(function(r) { return r.header('X-Test') + ':' + r.body(); }).valueOf()")

        XCTAssertEqual(try unwrap(result), "ajax:ajax-body")
    }

    func testAwaitJavaAjaxAllPreservesResponseList() throws {
        let runtime = fixtureRuntime { request in
            let url = request.contains("/one") ? "https://fixture.local/one" : "https://fixture.local/two"
            let name = url.split(separator: "/").last.map(String.init) ?? ""
            return self.response(body: name, url: url, headers: ["X-Source": name])
        }

        let result = runtime.evaluate("var list = await java.ajaxAll(['https://fixture.local/one', 'https://fixture.local/two']); list.map(function(r) { return r.body(); }).join(',')")

        XCTAssertEqual(try unwrap(result), "one,two")
    }

    func testAwaitJavaFetchAndGetStrResponse() throws {
        let runtime = fixtureRuntime { request in
            if request.contains("/fetch") {
                return self.response(body: "fetch-body", url: "https://fixture.local/fetch", headers: ["Content-Type": "text/plain"])
            }
            return self.response(body: "<h1>Title</h1>", url: "https://fixture.local/str", headers: [:])
        }

        let fetch = runtime.evaluate("await java.fetch('https://fixture.local/fetch').then(function(r) { return r.text(); }).valueOf()")
        let strResponse = runtime.evaluate("await java.getStrResponse('https://fixture.local/str', 'h1@text')")

        XCTAssertEqual(try unwrap(fetch), "fetch-body")
        XCTAssertEqual(try unwrap(strResponse), "Title")
    }

    func testPromiseResolveAllRaceAndRejectFacade() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            var resolved = Promise.resolve('ok').then(function(value) { return value + '!'; }).valueOf();
            var all = Promise.all([Promise.resolve('a'), 'b', Promise.resolve('c')]).then(function(values) { return values.join('-'); }).valueOf();
            var race = Promise.race([Promise.resolve('first'), Promise.resolve('second')]).valueOf();
            var rejected = Promise.reject('bad').catch(function(error) { return 'handled:' + error; }).valueOf();
            [resolved, all, race, rejected].join('|')
            """)

        XCTAssertEqual(try unwrap(result), "ok!|a-b-c|first|handled:bad")
    }

    func testAsyncFunctionAndArrowAreExecutableAfterNormalization() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            async function load(value) { return await Promise.resolve(value + '-fn'); }
            var arrow = async value => await Promise.resolve(value + '-arrow');
            [load('x').valueOf(), arrow('y').valueOf()].join('|')
            """)

        XCTAssertEqual(try unwrap(result), "x-fn|y-arrow")
    }

    func testURLSearchParamsHeadersAndResponseCompatibility() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            var params = new URLSearchParams('q=swift+ios&tag=one&tag=two');
            params.append('page', '2');
            var headers = new Headers({'X-Test': 'one'});
            headers.append('x-extra', 'two');
            headers.set('X-Test', 'updated');
            var response = new Response('{"title":"Book"}', {status: 201, url: 'https://fixture.local/book', headers: {'Content-Type': 'application/json'}});
            JSON.stringify({
              query: params.get('q'), tags: params.getAll('tag'), hasPage: params.has('page'),
              encoded: params.toString(), header: headers.get('x-test'), hasExtra: headers.has('X-EXTRA'),
              status: response.status, ok: response.ok, url: response.url,
              json: response.json().valueOf().title, body: response.text().valueOf()
            })
            """)

        let object = try jsonObject(unwrap(result))
        XCTAssertEqual(object["query"] as? String, "swift ios")
        XCTAssertEqual(object["tags"] as? [String], ["one", "two"])
        XCTAssertEqual(object["hasPage"] as? Bool, true)
        XCTAssertTrue(
            ["q=swift%20ios&tag=one&tag=two&page=2", "q=swift+ios&tag=one&tag=two&page=2"]
                .contains(object["encoded"] as? String ?? "")
        )
        XCTAssertEqual(object["header"] as? String, "updated")
        XCTAssertEqual(object["hasExtra"] as? Bool, true)
        XCTAssertEqual(object["status"] as? Int, 201)
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual(object["url"] as? String, "https://fixture.local/book")
        XCTAssertEqual(object["json"] as? String, "Book")
        XCTAssertEqual(object["body"] as? String, "{\"title\":\"Book\"}")
    }

    func testJavaScriptEvidenceCapturesFeaturesAndFailure() throws {
        let context = RuleExecutionContext()
        let runtime = JSCoreRuntime(executionContext: context)

        let success = runtime.evaluate("await Promise.resolve('ok')")
        XCTAssertEqual(try unwrap(success), "ok")
        let successEvidence = context.javascriptEvidenceSnapshot().last
        XCTAssertEqual(successEvidence?.succeeded, true)
        XCTAssertTrue(successEvidence?.features.contains("await") == true)
        XCTAssertTrue(successEvidence?.features.contains("promise") == true)

        let failure = runtime.evaluate("await Promise.resolve(missingLegadoValue)")
        guard case .failure(.javascript) = failure else {
            return XCTFail("expected JavaScript failure")
        }
        let failureEvidence = context.javascriptEvidenceSnapshot().last
        XCTAssertEqual(failureEvidence?.succeeded, false)
        XCTAssertNotNil(failureEvidence?.exception)
        XCTAssertTrue(failureEvidence?.features.contains("await") == true)
    }

    func testDiagnosticJSONRedactsSecretsInsideJavaScriptEvidence() throws {
        let evidence = SourceJavaScriptEvidence(
            originalScript: "var token = 'secret-token'; java.put('token', 'secret-token'); cookie.setCookie('sid=secret-cookie'); return token;",
            normalizedScript: "var token = 'secret-token'; java.put('token', 'secret-token'); cookie.setCookie('sid=secret-cookie'); return token;",
            features: ["await", "java.ajax"],
            exception: "Error: authorization='secret-auth'",
            succeeded: false
        )
        let step = SourceDiagnosticStep(
            stage: .search,
            status: .failed,
            javascript: [evidence],
            failureCode: .javascript
        )
        let data = try JSONEncoder().encode(step)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("<redacted>"))
        XCTAssertFalse(json.contains("secret-token"))
        XCTAssertFalse(json.contains("secret-cookie"))
        XCTAssertFalse(json.contains("secret-auth"))

        let decoded = try JSONDecoder().decode(SourceDiagnosticStep.self, from: data)
        XCTAssertEqual(decoded.javascript?.first?.succeeded, false)
        XCTAssertEqual(decoded.failureCode, .javascript)
    }

    func testEngineRunsAsyncBodyJsAndAttachesEvidenceToContentStage() async throws {
        let source = BookSource(
            bookSourceName: "Async body fixture",
            bookSourceUrl: "https://fixture.local/",
            ruleContent: SourceRule(fields: ["content": "#content@text"]),
            raw: [
                "bodyJs": "async function transform(value) { return await Promise.resolve(value.replace('ENCODED', '正文')); } transform(result)"
            ]
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://fixture.local/chapter/1",
            bookUrl: "https://fixture.local/book/1",
            index: 0,
            isVip: false
        )
        let engine = LegadoSourceEngine(network: AsyncBodyFixtureNetwork(body: "<div id='content'>ENCODED</div>"))

        let result = await engine.getContent(source: source, chapter: chapter)

        guard case .success(let content) = result else {
            return XCTFail("expected async body JS content: \(result)")
        }
        XCTAssertEqual(content.paragraphs, ["正文"])

        let evidence = try XCTUnwrap(engine.diagnosticEvidence(sourceURL: source.bookSourceUrl, stage: .content))
        let javascript = try XCTUnwrap(evidence.javascript.last)
        XCTAssertTrue(javascript.succeeded)
        XCTAssertTrue(javascript.features.contains("await"))
        XCTAssertTrue(javascript.features.contains("async"))
        XCTAssertTrue(javascript.features.contains("promise"))
        XCTAssertFalse(javascript.normalizedScript.contains("async function"))
    }
}

private extension LegadoJavaScriptCompatibilityTests {
    func fixtureRuntime(_ handler: @escaping (String) -> SourceResponse?) -> JSCoreRuntime {
        JSCoreRuntime(executionContext: RuleExecutionContext(responseHandler: handler))
    }

    func response(body: String, url: String, headers: [String: String]) -> SourceResponse {
        SourceResponse(
            url: URL(string: url)!,
            statusCode: 200,
            headers: headers,
            body: body,
            data: Data(body.utf8)
        )
    }

    func unwrap(_ result: Result<String, SourceEngineError>, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        guard case .success(let value) = result else {
            XCTFail("expected JavaScript success: \(result)", file: file, line: line)
            throw NSError(domain: "LegadoJavaScriptCompatibilityTests", code: 1)
        }
        return value
    }

    func jsonObject(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("expected JSON object: \(text)", file: file, line: line)
            throw NSError(domain: "LegadoJavaScriptCompatibilityTests", code: 2)
        }
        return object
    }
}

private final class AsyncBodyFixtureNetwork: SourceNetworkClient, @unchecked Sendable {
    private let body: String

    init(body: String) {
        self.body = body
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: body,
            data: Data(body.utf8)
        ))
    }
}
