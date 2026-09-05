import XCTest
@testable import SourceReadSwift

/// Stage 18 coverage for the Android Legado Java/HTTP host surface.  The
/// response handler is fully offline and records the exact directive passed to
/// the native request builder.
final class LegadoStage18CompatibilityTests: XCTestCase {
    func testConnectMethodsBodiesHeadersAndOutputStreamPreserveMethod() throws {
        let lock = NSLock()
        var requests: [String] = []
        let context = RuleExecutionContext(responseHandler: { encoded in
            lock.lock(); requests.append(encoded); lock.unlock()
            return SourceResponse(
                url: URL(string: "https://fixture.local/final")!,
                statusCode: 207,
                headers: ["X-Fixture": "stage18", "Content-Type": "text/plain"],
                body: "ok",
                data: Data([0, 255, 1, 2])
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("""
            var put = java.connect('https://fixture.local/put')
              .header('X-Put', '1').put('p=1').execute();
            var patch = java.connect('https://fixture.local/patch')
              .setRequestMethod('PATCH').requestBody('q=1').execute();
            var outputConnection = java.connect('https://fixture.local/output')
              .setRequestMethod('PUT');
            outputConnection.getOutputStream().write(java.strToBytes('raw=1'));
            var output = outputConnection.execute();
            var deleted = java.connect('https://fixture.local/delete')
              .delete('d=1');
            var fetched = java.fetch('https://fixture.local/fetch', {
              method: 'DELETE', body: 'f=1', headers: {'X-Fetch':'yes'}
            });
            JSON.stringify({
              putCode: put.statusCode(), patchCode: patch.statusCode(),
              outputCode: output.statusCode(), deleteCode: deleted.statusCode(),
              fetchCode: fetched.status,
              bytes: output.body().bytes().toArray(),
              header: fetched.header('x-fixture')
            })
            """)
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected HTTP bridge result: \(result)")
        }
        XCTAssertEqual(object["putCode"] as? Int, 207)
        XCTAssertEqual(object["patchCode"] as? Int, 207)
        XCTAssertEqual(object["outputCode"] as? Int, 207)
        XCTAssertEqual(object["deleteCode"] as? Int, 207)
        XCTAssertEqual(object["fetchCode"] as? Int, 207)
        XCTAssertEqual(object["bytes"] as? [Int], [0, 255, 1, 2])
        XCTAssertEqual(object["header"] as? String, "stage18")

        lock.lock(); let captured = requests; lock.unlock()
        XCTAssertEqual(captured.count, 5)
        XCTAssertTrue(captured[0].contains("\"method\":\"PUT\""))
        XCTAssertTrue(captured[0].contains("@Body:p=1"))
        XCTAssertTrue(captured[0].contains("@Header:{\"X-Put\":\"1\"}"))
        XCTAssertTrue(captured[1].contains("\"method\":\"PATCH\""))
        XCTAssertTrue(captured[1].contains("@Body:q=1"))
        XCTAssertTrue(captured[2].contains("\"method\":\"PUT\""))
        XCTAssertTrue(captured[2].contains("@Body:raw=1"))
        XCTAssertTrue(captured[3].contains("\"method\":\"DELETE\""))
        XCTAssertTrue(captured[4].contains("\"method\":\"DELETE\""))
        XCTAssertEqual(captured[4].components(separatedBy: "@Body:f=1").count - 1, 1)
    }

    func testResponseRawBytesFallbackAndMetadataAreStable() throws {
        let runtime = JSCoreRuntime(executionContext: RuleExecutionContext(responseHandler: { _ in
            SourceResponse(
                url: URL(string: "https://fixture.local/binary-final")!,
                statusCode: 206,
                headers: ["Content-Type": "application/octet-stream", "X-Stage": "18"],
                body: "fallback",
                data: Data([0, 255, 10])
            )
        }))
        let result = runtime.evaluate("""
            var response = java.ajax('https://fixture.local/binary');
            var all = java.ajaxAll(['https://fixture.local/binary']);
            JSON.stringify({
              status: response.status,
              finalUrl: response.finalUrl(),
              bytes: response.body().bytes().toArray(),
              allBytes: all.get(0).body().bytes().toArray(),
              contentType: response.header('content-type'),
              trace: response.header('x-stage')
            })
            """)
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected response metadata result: \(result)")
        }
        XCTAssertEqual(object["status"] as? Int, 206)
        XCTAssertEqual(object["finalUrl"] as? String, "https://fixture.local/binary-final")
        XCTAssertEqual(object["bytes"] as? [Int], [0, 255, 10])
        XCTAssertEqual(object["allBytes"] as? [Int], [0, 255, 10])
        XCTAssertEqual(object["contentType"] as? String, "application/octet-stream")
        XCTAssertEqual(object["trace"] as? String, "18")
    }

    func testFetchMethodOverridesExistingDirectiveOptionsWithoutDuplicatingSuffix() throws {
        let lock = NSLock()
        var requests: [String] = []
        let context = RuleExecutionContext(responseHandler: { encoded in
            lock.lock(); requests.append(encoded); lock.unlock()
            return SourceResponse(
                url: URL(string: "https://fixture.local/override-final")!,
                statusCode: 200,
                headers: [:],
                body: "ok",
                data: Data("ok".utf8)
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("""
            var response = java.fetch('https://fixture.local/override,{"method":"GET","headers":{"X-Existing":"1"}}', {
              method: 'PATCH', body: 'x=1', headers: {'X-New':'2'}
            });
            JSON.stringify({status: response.status, body: response.text()})
            """)
        guard case .success(let value) = result else {
            return XCTFail("expected method override result: \(result)")
        }
        XCTAssertTrue(value.contains("\"status\":200"))
        lock.lock(); let captured = requests; lock.unlock()
        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured[0].contains("\"method\":\"PATCH\""))
        XCTAssertTrue(captured[0].contains("\"X-Existing\":\"1\""))
        XCTAssertTrue(captured[0].contains("\"X-New\":\"2\""))
        XCTAssertEqual(captured[0].components(separatedBy: ",{").count - 1, 1)
        XCTAssertEqual(captured[0].components(separatedBy: "@Body:x=1").count - 1, 1)
    }

    func testConnectSupportsHeadOptionsAndSourceRequestOptionsMethods() throws {
        let lock = NSLock()
        var requests: [String] = []
        let context = RuleExecutionContext(responseHandler: { encoded in
            lock.lock(); requests.append(encoded); lock.unlock()
            return SourceResponse(
                url: URL(string: "https://fixture.local/method-final")!,
                statusCode: 204,
                headers: [:],
                body: "",
                data: Data()
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("""
            var head = java.connect('https://fixture.local/head').head().execute();
            var options = java.connect('https://fixture.local/options').options().execute();
            JSON.stringify({head: head.status, options: options.status})
            """)
        guard case .success(let value) = result else {
            return XCTFail("expected HEAD/OPTIONS result: \(result)")
        }
        XCTAssertTrue(value.contains("\"head\":204"))
        XCTAssertTrue(value.contains("\"options\":204"))
        lock.lock(); let captured = requests; lock.unlock()
        XCTAssertEqual(captured.count, 2)
        XCTAssertTrue(captured[0].contains("\"method\":\"HEAD\""))
        XCTAssertTrue(captured[1].contains("\"method\":\"OPTIONS\""))

        let source = BookSource(
            bookSourceName: "Method options",
            bookSourceUrl: "https://fixture.local",
            searchUrl: "https://fixture.local/api",
            customConfig: #"{"method":"OPTIONS","body":"probe=1"}"#
        )
        let request = SourceRequestBuilder().buildSearchRequest(
            source: source,
            searchUrl: source.searchUrl!,
            keyword: "ignored",
            page: 1
        )
        XCTAssertEqual(request.method, .options)
        XCTAssertEqual(String(data: request.body ?? Data(), encoding: .utf8), "probe=1")
    }

    func testImportScriptURLAndSourceBookChapterVariables() throws {
        let context = RuleExecutionContext(responseHandler: { encoded in
            XCTAssertTrue(encoded.contains("https://fixture.local/import.js"))
            return SourceResponse(
                url: URL(string: "https://fixture.local/import.js")!,
                statusCode: 200,
                headers: ["Content-Type": "text/javascript"],
                body: "function importedValue(){ return 'fixture-imported'; }",
                data: Data("function importedValue(){ return 'fixture-imported'; }".utf8)
            )
        })
        let source = BookSource(bookSourceName: "Stage18", bookSourceUrl: "https://fixture.local/source")
        let book = SearchBook(
            name: "Book", author: "Author", coverUrl: nil,
            bookUrl: "https://fixture.local/book", sourceName: "Stage18", sourceUrl: source.bookSourceUrl, intro: nil
        )
        let chapter = BookChapter(title: "Chapter", url: "https://fixture.local/chapter", bookUrl: book.bookUrl, index: 3, isVip: false)
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("""
            java.importScript('https://fixture.local/import.js');
            source.setVariable('token', 'source-token');
            book.setVariable('cursor', 'book-cursor');
            chapter.setVariable('page', 'chapter-page');
            JSON.stringify({
              imported: importedValue(),
              sourceToken: source.getVariable('token'),
              bookCursor: book.getVariable('cursor'),
              chapterPage: chapter.getVariable('page'),
              mapValue: source.getVariableMap().get('token')
            })
            """, variables: ["source": source, "book": book, "chapter": chapter])
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected import/variable result: \(result)")
        }
        XCTAssertEqual(object["imported"] as? String, "fixture-imported")
        XCTAssertEqual(object["sourceToken"] as? String, "source-token")
        XCTAssertEqual(object["bookCursor"] as? String, "book-cursor")
        XCTAssertEqual(object["chapterPage"] as? String, "chapter-page")
        XCTAssertEqual(object["mapValue"] as? String, "source-token")
    }
}
