import XCTest
@testable import SourceReadSwift

/// Stage 5 compatibility coverage for the high-frequency Android Legado JS
/// surface.  All network calls are deterministic local fixtures so CI never
/// depends on a public source or an external service.
final class LegadoJavaCompatibilityTests: XCTestCase {
    func testGlobalAliasesAndHTMLHelpers() throws {
        let html = "<div class='book'><a href='/b1'><span class='title'>Book One</span></a></div><div class='book'><a href='/b2'><span class='title'>Book Two</span></a></div>"
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            JSON.stringify({
              count: select(result, '.book').length,
              firstTitle: selectFirst(result, '.title'),
              href: getAttr(result, '.book a', 'href'),
              cleaned: clean('<p>A</p><p>B</p>'),
              md5: md5Encode('abc'),
              sha1: sha1Encode('abc'),
              sha256: sha256Encode('abc'),
              roundTrip: base64Decode(base64Encode('hello')),
              ua: getWebViewUA().indexOf('Mozilla') >= 0,
              aliases: [typeof fetch, typeof request, typeof ajax, typeof importScript].join('|')
            })
            """, variables: ["result": html])

        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected JSON helper result")
        }
        XCTAssertEqual(object["count"] as? Int, 2)
        XCTAssertEqual(object["firstTitle"] as? String, "Book One")
        XCTAssertEqual(object["href"] as? String, "/b1")
        XCTAssertEqual(object["cleaned"] as? String, "A\nB")
        XCTAssertEqual(object["md5"] as? String, "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(object["sha1"] as? String, "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(object["sha256"] as? String, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(object["roundTrip"] as? String, "hello")
        XCTAssertEqual(object["ua"] as? Bool, true)
        XCTAssertEqual(object["aliases"] as? String, "function|function|function|function")
    }

    func testJavaRegexReplaceMatchAllAndInvalidPattern() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            var replaced = java.regex.replace('A12B34', '\\\\d+', '#');
            var matches = java.regex.matchAll('A12B34', '\\\\d+');
            var tested = java.regex.test('A12', '\\\\d+');
            var invalid = java.regex.replace('safe', '[', '#');
            JSON.stringify({replaced: replaced, matches: matches, tested: tested, invalid: invalid})
            """)
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected regex result")
        }
        XCTAssertEqual(object["replaced"] as? String, "A#B#")
        XCTAssertEqual(object["matches"] as? [String], ["12", "34"])
        XCTAssertEqual(object["tested"] as? Bool, true)
        XCTAssertEqual(object["invalid"] as? String, "safe")
    }

    func testJavaUtilPatternMatcherSupportsFindGroupsAndFlags() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("""
            var matcher = Packages.java.util.regex.Pattern.compile('(a)(b)', 2).matcher('AB ab xx');
            var found = [];
            while (matcher.find()) found.push(matcher.group(1) + matcher.group(2) + '@' + matcher.start() + ':' + matcher.end());
            var exact = Packages.java.util.regex.Pattern.compile('hello').matcher('hello');
            var exactMatches = exact.matches();
            JSON.stringify({found: found, exact: exactMatches, exactGroup: exact.group()})
            """)
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected Pattern matcher result")
        }
        XCTAssertEqual(object["found"] as? [String], ["AB@0:2", "ab@3:5"])
        XCTAssertEqual(object["exact"] as? Bool, true)
        XCTAssertEqual(object["exactGroup"] as? String, "hello")
    }

    func testJSONPathFiltersAndRecursiveDescent() throws {
        let runtime = JSCoreRuntime()
        let json = """
            {"payload":{"nested":{"bookList":[{"name":"A","hasContent":1,"source":"free"},{"name":"B","hasContent":0,"source":"vip"},{"name":"C","hasContent":true,"source":"free"}]}}}
            """
        let result = runtime.evaluate("""
            JSON.stringify({
              names: java.getStringList(result, '$..bookList[*].name'),
              truthy: java.getStringList(result, '$.payload.nested.bookList[?(@.hasContent)].name'),
              free: java.getStringList(result, '$.payload.nested.bookList[?(@.source!=\"vip\")].name')
            })
            """, variables: ["result": json])
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected JSONPath result")
        }
        XCTAssertEqual(object["names"] as? [String], ["A", "B", "C"])
        XCTAssertEqual(object["truthy"] as? [String], ["A", "C"])
        XCTAssertEqual(object["free"] as? [String], ["A", "C"])
    }

    func testResponseAliasesAndFetchRequestOptions() throws {
        var requests: [String] = []
        let context = RuleExecutionContext(responseHandler: { encoded in
            requests.append(encoded)
            let isPost = encoded.contains("@Body:q=1")
            let body = isPost ? "{\"ok\":true}" : "{\"title\":\"Fetched\"}"
            return SourceResponse(
                url: URL(string: isPost ? "https://fixture.local/post-final" : "https://fixture.local/get-final")!,
                statusCode: isPost ? 201 : 206,
                headers: ["X-Trace": "fixture", "Content-Type": "application/json"],
                body: body,
                data: Data(body.utf8)
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("""
            var get = fetch('https://fixture.local/get');
            var post = request('https://fixture.local/api', {method:'post', body:'q=1', headers:{'X-App':'reader'}});
            JSON.stringify({
              matched: get.match(/title\\\":\\\"(.*?)\\\"/)[1],
              body: get.body().string(),
              parsed: get.body().json().title,
              parsedDirect: get.json().title,
              code: get.statusCode(),
              legacyCode: Number(get.statusCode),
              aliasCode: get.code,
              status: get.status,
              ok: get.ok,
              finalUrl: get.finalUrl(),
              header: get.header('x-trace'),
              postOK: post.json().ok
            })
            """)
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected response result")
        }
        XCTAssertEqual(object["matched"] as? String, "Fetched")
        XCTAssertEqual(object["body"] as? String, "{\"title\":\"Fetched\"}")
        XCTAssertEqual(object["parsed"] as? String, "Fetched")
        XCTAssertEqual(object["parsedDirect"] as? String, "Fetched")
        XCTAssertEqual(object["code"] as? Int, 206)
        XCTAssertEqual(object["legacyCode"] as? Int, 206)
        XCTAssertEqual(object["aliasCode"] as? Int, 206)
        XCTAssertEqual(object["status"] as? Int, 206)
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual(object["finalUrl"] as? String, "https://fixture.local/get-final")
        XCTAssertEqual(object["header"] as? String, "fixture")
        XCTAssertEqual(object["postOK"] as? Bool, true)
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[1].contains("https://fixture.local/api"))
        XCTAssertTrue(requests[1].contains("\"method\":\"POST\""))
        XCTAssertTrue(requests[1].contains("\"body\":\"q=1\""))
        XCTAssertTrue(requests[1].contains("\"X-App\":\"reader\""))
    }

    func testJavaConnectCookieImportScriptAndContentMutation() throws {
        var requests: [String] = []
        let context = RuleExecutionContext(responseHandler: { encoded in
            requests.append(encoded)
            if encoded.contains("/library") {
                return SourceResponse(
                    url: URL(string: "https://fixture.local/library")!,
                    statusCode: encoded.contains("@Body:q=1") ? 201 : 200,
                    headers: ["Set-Cookie": "sid=fixture"],
                    body: "{\"items\":[{\"title\":\"One\"},{\"title\":\"Two\"}]}",
                    data: Data()
                )
            }
            return SourceResponse(
                url: URL(string: "https://fixture.local/content")!,
                statusCode: 200,
                headers: [:],
                body: "<div id='content'><p>Old</p></div>",
                data: Data()
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("""
            java.importScript('data:text/javascript,function importedTitle(){return "imported";}');
            cookie.setCookie('sid=1');
            var response = java.connect('https://fixture.local/library').header('X-Test','1').post('q=1');
            var json = response.json();
            java.setContent('<div id="content"><p>New</p></div>');
            var node = java.getElement('#content p');
            JSON.stringify({
              title: java.getString(response.body().string(), '$.items[0].title'),
              imported: importedTitle(),
              cookie: java.getCookie(),
              content: node.text(),
              responseCode: response.statusCode()
            })
            """)
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected connect result")
        }
        XCTAssertEqual(object["title"] as? String, "One")
        XCTAssertEqual(object["imported"] as? String, "imported")
        XCTAssertEqual(object["cookie"] as? String, "sid=1")
        XCTAssertEqual(object["content"] as? String, "New")
        XCTAssertEqual(object["responseCode"] as? Int, 201)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].contains("@Body:q=1"))
        XCTAssertTrue(requests[0].contains("\"X-Test\":\"1\""))
    }
}
