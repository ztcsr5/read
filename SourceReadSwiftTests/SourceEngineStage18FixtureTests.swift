import XCTest
@testable import SourceReadSwift

/// Stage 18 pagination and failure-observation coverage. Fixtures never leave
/// the process and the client records every request for exact stop assertions.
final class SourceEngineStage18FixtureTests: XCTestCase {
    func testTOCPaginationStopsOnDuplicateURLAndKeepsPrefix() async throws {
        let source = paginationSource()
        let first = "https://fixture.local/toc/1"
        let second = "https://fixture.local/toc/2"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div class='chapter'><a href='/chapter/1'>一</a></div><a class='next' href='/toc/2'>next</a>"),
            second: html("<div class='chapter'><a href='/chapter/2'>二</a></div><a class='next' href='/toc/2'>next</a>")
        ])
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let detail = BookDetail(name: "Paged", author: nil, coverUrl: nil, bookUrl: "https://fixture.local/book", tocUrl: first, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)

        let result = await engine.getChapterList(source: source, book: detail)
        guard case .success(let chapters) = result else { return XCTFail("expected chapters: \(result)") }
        XCTAssertEqual(chapters.map(\.title), ["一", "二"])
        XCTAssertEqual(network.requestedURLs, [first, second])
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "toc.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "duplicate-url")
        XCTAssertEqual(stop.details["pagesLoaded"], "2")
    }

    func testTOCPaginationStopsAtThirtyPages() async throws {
        let source = paginationSource()
        var responses: [String: Stage18FixtureNetwork.Payload] = [:]
        for page in 1...31 {
            let url = "https://fixture.local/toc/\(page)"
            let next = page < 31 ? "<a class='next' href='/toc/\(page + 1)'>next</a>" : ""
            responses[url] = html("<div class='chapter'><a href='/chapter/\(page)'>\(page)</a></div>\(next)")
        }
        let network = Stage18FixtureNetwork(responses: responses)
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let detail = BookDetail(name: "Paged", author: nil, coverUrl: nil, bookUrl: "https://fixture.local/book", tocUrl: "https://fixture.local/toc/1", sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)

        let result = await engine.getChapterList(source: source, book: detail)
        guard case .success(let chapters) = result else { return XCTFail("expected chapters: \(result)") }
        XCTAssertEqual(chapters.count, 30)
        XCTAssertEqual(network.requests.count, 30)
        XCTAssertFalse(network.requestedURLs.contains("https://fixture.local/toc/31"))
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "toc.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "max-pages")
        XCTAssertEqual(stop.details["pagesLoaded"], "30")
        XCTAssertEqual(stop.details["maxPages"], "30")
    }

    func testContentPaginationStopsOnDuplicateAndRetainsSuccessfulParagraphs() async throws {
        let source = paginationSource()
        let first = "https://fixture.local/content/1"
        let second = "https://fixture.local/content/2"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div id='content'>页一</div><a class='next' href='/content/2'>next</a>"),
            second: html("<div id='content'>页二</div><a class='next' href='/content/2'>next</a>")
        ])
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let chapter = BookChapter(title: "Chapter", url: first, bookUrl: "https://fixture.local/book", index: 0, isVip: false)

        let result = await engine.getContent(source: source, chapter: chapter)
        guard case .success(let content) = result else { return XCTFail("expected content: \(result)") }
        XCTAssertEqual(content.paragraphs, ["页一", "页二"])
        XCTAssertNil(content.nextContentUrl)
        XCTAssertEqual(network.requestedURLs, [first, second])
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "content.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "duplicate-url")
        XCTAssertEqual(stop.details["pagesLoaded"], "2")
    }

    func testContentPaginationStopsAtEightPages() async throws {
        let source = paginationSource()
        var responses: [String: Stage18FixtureNetwork.Payload] = [:]
        for page in 1...9 {
            let url = "https://fixture.local/content/\(page)"
            let next = page < 9 ? "<a class='next' href='/content/\(page + 1)'>next</a>" : ""
            responses[url] = html("<div id='content'>页\(page)</div>\(next)")
        }
        // Page eight points to page nine so the engine has a pending next URL
        // when its safety cap is reached.
        responses["https://fixture.local/content/8"] = html("<div id='content'>页8</div><a class='next' href='/content/9'>next</a>")
        let network = Stage18FixtureNetwork(responses: responses)
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let chapter = BookChapter(title: "Chapter", url: "https://fixture.local/content/1", bookUrl: "https://fixture.local/book", index: 0, isVip: false)

        let result = await engine.getContent(source: source, chapter: chapter)
        guard case .success(let content) = result else { return XCTFail("expected content: \(result)") }
        XCTAssertEqual(content.paragraphs, (1...8).map { "页\($0)" })
        XCTAssertNil(content.nextContentUrl)
        XCTAssertEqual(network.requests.count, 8)
        XCTAssertFalse(network.requestedURLs.contains("https://fixture.local/content/9"))
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "content.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "max-pages")
        XCTAssertEqual(stop.details["pagesLoaded"], "8")
    }

    private func paginationSource() -> BookSource {
        BookSource(
            bookSourceName: "Stage18 pagination",
            bookSourceUrl: "https://fixture.local",
            ruleToc: SourceRule(fields: ["chapterList": ".chapter", "chapterName": "a@text", "chapterUrl": "a@href", "nextTocUrl": "a.next@href"]),
            ruleContent: SourceRule(fields: ["content": "#content@text", "nextContentUrl": "a.next@href"])
        )
    }

    private func html(_ body: String) -> Stage18FixtureNetwork.Payload {
        .init(body: "<html><body>\(body)</body></html>")
    }
}

private final class Stage18FixtureNetwork: SourceNetworkClient, @unchecked Sendable {
    struct Payload: Sendable {
        let body: String
        init(body: String) { self.body = body }
    }

    private let responses: [String: Payload]
    private let lock = NSLock()
    private var recorded: [SourceRequest] = []

    init(responses: [String: Payload]) { self.responses = responses }

    var requests: [SourceRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var requestedURLs: [String] { requests.map(\.url.absoluteString) }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lock.lock(); recorded.append(request); lock.unlock()
        guard let payload = responses[request.url.absoluteString] else {
            return .failure(.network("fixture missing: \(request.url.absoluteString)"))
        }
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: ["Content-Type": "text/html"],
            body: payload.body,
            data: Data(payload.body.utf8)
        ))
    }
}

private final class Stage18Diagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DiagnosticEvent] = []

    var events: [DiagnosticEvent] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func append(_ event: DiagnosticEvent) {
        lock.lock(); stored.append(event); lock.unlock()
    }
}
