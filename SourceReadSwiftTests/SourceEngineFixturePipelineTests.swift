import Foundation
import XCTest
@testable import SourceReadSwift

/// End-to-end source-engine coverage using deterministic local responses.
/// These tests deliberately exercise the same public pipeline used by the UI:
/// search -> detail -> TOC -> content.  No external source is contacted.
final class SourceEngineFixturePipelineTests: XCTestCase {
    func testHTMLFixtureRunsSearchDetailTOCAndContent() async throws {
        let source = try loadFixture(named: "legado-html-source")
        let searchURL = "https://fixture.example/search?q=swift&page=1"
        let bookURL = "https://fixture.example/book/html-1"
        let chapterURL = "https://fixture.example/chapter/html-1"
        let network = FixtureNetworkClient(responses: [
            searchURL: .text("""
                <html><body><div class="book"><h2>Swift Reader</h2><span class="author">Fixture Author</span><a href="/book/html-1">open</a></div></body></html>
                """),
            bookURL: .text("""
                <html><body><h1>Swift Reader</h1><a class="toc" href="/book/html-1/toc">目录</a></body></html>
                """),
            "https://fixture.example/book/html-1/toc": .text("""
                <html><body><div class="chapter"><a href="/chapter/html-1">第一章</a></div></body></html>
                """),
            chapterURL: .text("<html><body><div id='content'>第一段<br>第二段</div></body></html>")
        ])
        let engine = LegadoSourceEngine(network: network)

        let books = try await unwrap(engine.searchBooks(source: source, keyword: "swift", page: 1))
        XCTAssertEqual(books.map(\.name), ["Swift Reader"])
        XCTAssertEqual(books.first?.bookUrl, bookURL)

        let detail = try await unwrap(engine.getBookDetail(source: source, book: try XCTUnwrap(books.first)))
        XCTAssertEqual(detail.name, "Swift Reader")
        XCTAssertEqual(detail.tocUrl, "https://fixture.example/book/html-1/toc")

        let chapters = try await unwrap(engine.getChapterList(source: source, book: detail))
        XCTAssertEqual(chapters.map(\.title), ["第一章"])
        XCTAssertEqual(chapters.first?.url, chapterURL)

        let content = try await unwrap(engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))
        XCTAssertEqual(content.paragraphs, ["第一段", "第二段"])
        XCTAssertEqual(network.requestedURLs, [searchURL, bookURL, "https://fixture.example/book/html-1/toc", chapterURL])
    }

    func testJSONFixtureRunsSearchDetailTOCAndContent() async throws {
        let source = try loadFixture(named: "legado-json-source")
        let searchURL = "https://fixture.example/api?q=swift"
        let bookURL = "https://fixture.example/book/json-1"
        let tocURL = "https://fixture.example/book/json-1/toc"
        let chapterURL = "https://fixture.example/chapter/json-1"
        let network = FixtureNetworkClient(responses: [
            searchURL: .json(#"{"data":{"books":[{"name":"JSON Reader","author":"API Author","url":"/book/json-1"}]}}"#),
            bookURL: .json(#"{"name":"JSON Reader","author":"API Author","intro":"JSON intro","toc":"/book/json-1/toc"}"#),
            tocURL: .json(#"{"chapters":[{"title":"第一节","url":"/chapter/json-1"}]}"#),
            chapterURL: .json(#"{"content":"JSON 第一段\nJSON 第二段"}"#)
        ])
        let engine = LegadoSourceEngine(network: network)

        let books = try await unwrap(engine.searchBooks(source: source, keyword: "swift", page: 1))
        XCTAssertEqual(books.first?.name, "JSON Reader")
        XCTAssertEqual(books.first?.bookUrl, bookURL)
        let detail = try await unwrap(engine.getBookDetail(source: source, book: try XCTUnwrap(books.first)))
        XCTAssertEqual(detail.intro, "JSON intro")
        XCTAssertEqual(detail.tocUrl, tocURL)
        let chapters = try await unwrap(engine.getChapterList(source: source, book: detail))
        XCTAssertEqual(chapters.first?.url, chapterURL)
        let content = try await unwrap(engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))
        XCTAssertEqual(content.paragraphs, ["JSON 第一段", "JSON 第二段"])
    }

    func testJavaScriptFixtureParsesStringifiedBookListAndBodyTransformation() async throws {
        let source = try loadFixture(named: "legado-js-source")
        let searchURL = "https://fixture.example/api?q=swift"
        let bookURL = "https://fixture.example/book"
        let chapterURL = "https://fixture.example/chapter/js-1"
        let network = FixtureNetworkClient(responses: [
            searchURL: .json(#"{"ok":true}"#),
            bookURL: .text("<html><body><h1>JS Book</h1></body></html>"),
            chapterURL: .text("<html><body><article>A</article></body></html>")
        ])
        let engine = LegadoSourceEngine(network: network)

        let books = try await unwrap(engine.searchBooks(source: source, keyword: "swift", page: 1))
        XCTAssertEqual(books.map(\.name), ["JS Book"])
        XCTAssertEqual(books.first?.bookUrl, bookURL)
        let detail = try await unwrap(engine.getBookDetail(source: source, book: try XCTUnwrap(books.first)))
        XCTAssertEqual(detail.name, "JS Book")
        let chapter = BookChapter(title: "JS 第一章", url: chapterURL, bookUrl: bookURL, index: 0, isVip: false)
        let content = try await unwrap(engine.getContent(source: source, chapter: chapter))
        XCTAssertEqual(content.paragraphs, ["B"])
    }

    func testPOSTFixtureBuildsMethodBodyAndSearchPipeline() async throws {
        let source = try loadFixture(named: "legado-post-source")
        let network = FixtureNetworkClient(responses: [
            "https://fixture.example/search": .json(#"{"data":[{"title":"POST Reader","url":"/book/post-1"}]}"#)
        ])
        let engine = LegadoSourceEngine(network: network)
        let books = try await unwrap(engine.searchBooks(source: source, keyword: "swift", page: 1))

        XCTAssertEqual(books.first?.name, "POST Reader")
        let request = try XCTUnwrap(network.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://fixture.example/search")
        XCTAssertEqual(request.method.rawValue, "POST")
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), "keyword=swift")
    }

    func testHeadersCookieStatusAndFailureDiagnosticsAreObservable() async throws {
        let source = BookSource(
            bookSourceName: "Header fixture",
            bookSourceUrl: "https://fixture.example",
            searchUrl: "https://fixture.example/cookie?q={{key}}",
            ruleSearch: SourceRule(fields: [
                "bookList": "$.data",
                "name": "$.name",
                "bookUrl": "$.url"
            ]),
            header: #"{"X-Source":"fixture","User-Agent":"SourceReadTests/1"}"#,
            raw: ["cookie": "session=fixture"]
        )
        let diagnostics = FixtureDiagnostics()
        let network = FixtureNetworkClient(responses: [
            "https://fixture.example/cookie?q=%E4%B9%A6": .json(#"{"data":[{"name":"Header Reader","url":"/book/header"}]}"#)
        ])
        let engine = LegadoSourceEngine(
            network: network,
            diagnostics: DiagnosticSink { event in diagnostics.append(event) }
        )

        let books = try await unwrap(engine.searchBooks(source: source, keyword: "书", page: 1))
        XCTAssertEqual(books.first?.bookUrl, "https://fixture.example/book/header")
        let request = try XCTUnwrap(network.requests.first)
        XCTAssertEqual(request.headers["X-Source"], "fixture")
        XCTAssertEqual(request.headers["User-Agent"], "SourceReadTests/1")
        XCTAssertEqual(request.headers["Cookie"], "session=fixture")
        let responseEvent = try XCTUnwrap(diagnostics.events.first { $0.stage == "search.load.response" })
        XCTAssertEqual(responseEvent.details["status"], "200")
        XCTAssertEqual(responseEvent.details["setCookie"], "present")

        let emptyDiagnostics = FixtureDiagnostics()
        let emptyEngine = LegadoSourceEngine(
            network: FixtureNetworkClient(responses: [
                "https://fixture.example/cookie?q=empty": .text("")
            ]),
            diagnostics: DiagnosticSink { event in emptyDiagnostics.append(event) }
        )
        let failure = await emptyEngine.searchBooks(source: source, keyword: "empty", page: 1)
        guard case .failure(.empty(let message)) = failure else {
            return XCTFail("expected empty-response classification, got \(failure)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(emptyDiagnostics.events.contains { $0.stage == "search.empty" && $0.level == .warning })
    }

    func testPaginationFixtureCombinesTOCAndContentPagesWithRenumberedIndexes() async throws {
        let source = try loadFixture(named: "legado-html-pagination-source")
        let detail = BookDetail(
            name: "Paged Fixture", author: nil, coverUrl: nil,
            bookUrl: "https://fixture.example/book/paged",
            tocUrl: "https://fixture.example/pagination/toc-1",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl,
            intro: nil, latestChapter: nil
        )
        let chapterURL = "https://fixture.example/chapter/paged-1"
        let network = FixtureNetworkClient(responses: [
            "https://fixture.example/pagination/toc-1": .text("<html><body><div class='chapter'><a href='/chapter/paged-1'>一</a></div><a class='next' href='/pagination/toc-2'>下一页</a></body></html>"),
            "https://fixture.example/pagination/toc-2": .text("<html><body><div class='chapter'><a href='/chapter/paged-2'>二</a></div></body></html>"),
            chapterURL: .text("<html><body><div id='content'>页一</div><a class='next' href='/chapter/paged-1-2'>下一页</a></body></html>"),
            "https://fixture.example/chapter/paged-1-2": .text("<html><body><div id='content'>页二</div></body></html>")
        ])
        let engine = LegadoSourceEngine(network: network)

        let chapters = try await unwrap(engine.getChapterList(source: source, book: detail))
        XCTAssertEqual(chapters.map(\.title), ["一", "二"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        let content = try await unwrap(engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))
        XCTAssertEqual(content.paragraphs, ["页一", "页二"])
        XCTAssertNil(content.nextContentUrl)
    }

    func testJXNodeFixtureUsesHTMLContentAndDiagnosticsCaptureRequestMetadata() async throws {
        let source = try loadFixture(named: "legado-jxnode-source")
        let diagnostics = FixtureDiagnostics()
        let network = FixtureNetworkClient(responses: [
            "https://fixture.example/search?q=swift": .json(#"{"ok":true}"#),
            "https://fixture.example/node": .text("<html><body><div class='content'>JXNode 内容</div></body></html>")
        ])
        let engine = LegadoSourceEngine(
            network: network,
            diagnostics: DiagnosticSink { event in diagnostics.append(event) }
        )

        let books = try await unwrap(engine.searchBooks(source: source, keyword: "swift", page: 1))
        let chapter = BookChapter(title: "Node", url: "https://fixture.example/node", bookUrl: try XCTUnwrap(books.first?.bookUrl), index: 0, isVip: false)
        let content = try await unwrap(engine.getContent(source: source, chapter: chapter))
        XCTAssertEqual(content.paragraphs, ["JXNode 内容"])
        let events = diagnostics.events
        XCTAssertTrue(events.contains { $0.stage == "search.load.response" && $0.details["method"] == "GET" })
        XCTAssertTrue(events.contains { $0.stage == "content.load.response" && $0.details["status"] == "200" })
    }

    private func loadFixture(named name: String) throws -> BookSource {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "json")
        )
        return try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: url))
    }

    private func unwrap<T>(_ result: Result<T, SourceEngineError>, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("source pipeline failed: \(error)", file: file, line: line)
            throw error
        }
    }
}

private final class FixtureNetworkClient: SourceNetworkClient, @unchecked Sendable {
    enum Payload: Sendable {
        case text(String)
        case json(String)

        var body: String {
            switch self {
            case .text(let value), .json(let value): return value
            }
        }
    }

    private let responses: [String: Payload]
    private let lock = NSLock()
    private var recordedRequests: [SourceRequest] = []

    init(responses: [String: Payload]) {
        self.responses = responses
    }

    var requests: [SourceRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    var requestedURLs: [String] {
        requests.map { $0.url.absoluteString }
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()
        guard let payload = responses[request.url.absoluteString] else {
            return .failure(.network("fixture response missing for \(request.url.absoluteString)"))
        }
        let body = payload.body
        let contentType = body.first == "{" || body.first == "[" ? "application/json" : "text/html"
        var headers = ["Content-Type": contentType]
        if request.url.path.contains("cookie") {
            headers["Set-Cookie"] = "fixture=present; Path=/"
        }
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: headers,
            body: body,
            data: Data(body.utf8)
        ))
    }
}

private final class FixtureDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [DiagnosticEvent] = []

    var events: [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    func append(_ event: DiagnosticEvent) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }
}
