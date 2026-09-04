import Foundation
import XCTest
@testable import SourceReadSwift

/// Offline, end-to-end probes for the four source shapes added in Stage 11.
/// These deliberately use the same public engine methods as the UI and never
/// contact a real source host.
final class SourceEngineLegadoCorpusTests: XCTestCase {
    func testMixedResponseFixtureRunsFourStages() async throws {
        let source = try loadFixture(named: "legado-mixed-response-source")
        let searchURL = "https://fixture.example/mixed/search?q=%E6%B7%B7%E5%90%88"
        let bookURL = "https://fixture.example/mixed/book/1"
        let tocURL = "https://fixture.example/mixed/toc/1"
        let chapterURL = "https://fixture.example/mixed/chapter/1"
        let network = CorpusNetworkClient(responses: [
            searchURL: .init(body: "\u{FEFF})]}',<pre>prefix {\"data\":{\"items\":[{\"title\":\"混合书\",\"author\":\"Fixture\",\"url\":\"/mixed/book/1\"}]}}</pre>", contentType: "text/html"),
            bookURL: .init(body: "\u{FEFF}<pre>prefix {\"title\":\"混合书\",\"toc\":\"/mixed/toc/1\"}</pre>", contentType: "text/html"),
            tocURL: .init(body: "\u{FEFF}<pre>prefix {\"chapters\":[{\"title\":\"第一章\",\"url\":\"/mixed/chapter/1\"}]}</pre>", contentType: "text/html"),
            chapterURL: .init(body: "\u{FEFF}<pre>prefix {\"content\":\"混合正文\"}</pre>", contentType: "text/html")
        ])
        let engine = LegadoSourceEngine(network: network)

        let books = try unwrap(await engine.searchBooks(source: source, keyword: "混合", page: 1))
        XCTAssertEqual(books.map(\.name), ["混合书"])
        XCTAssertEqual(books.first?.bookUrl, bookURL)
        let detail = try unwrap(await engine.getBookDetail(source: source, book: try XCTUnwrap(books.first)))
        XCTAssertEqual(detail.tocUrl, tocURL)
        let chapters = try unwrap(await engine.getChapterList(source: source, book: detail))
        XCTAssertEqual(chapters.first?.url, chapterURL)
        let content = try unwrap(await engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))
        XCTAssertEqual(content.paragraphs, ["混合正文"])
        XCTAssertEqual(network.requestedURLs, [searchURL, bookURL, tocURL, chapterURL])
    }

    func testCookieTokenFixtureCarriesJavaStateAndResponseCookieAcrossStages() async throws {
        let source = try loadFixture(named: "legado-cookie-token-source")
        let searchURL = "https://fixture.example/cookie-token/search"
        let bookURL = "https://fixture.example/cookie-token/book/1"
        let tocURL = "https://fixture.example/cookie-token/toc/1"
        let chapterURL = "https://fixture.example/cookie-token/chapter/1"
        let network = CorpusNetworkClient(responses: [
            searchURL: .init(body: #"{"books":[{"name":"Cookie Reader","url":"/cookie-token/book/1"}]}"#, setCookie: "sid=fixture; Path=/"),
            bookURL: .init(body: #"{"name":"Cookie Reader","toc":"/cookie-token/toc/1"}"#),
            tocURL: .init(body: #"{"chapters":[{"title":"第一章","url":"/cookie-token/chapter/1"}]}"#),
            chapterURL: .init(body: #"{"content":"Cookie 正文"}"#)
        ])
        let engine = LegadoSourceEngine(network: network)

        let books = try unwrap(await engine.searchBooks(source: source, keyword: "cookie", page: 1))
        let detail = try unwrap(await engine.getBookDetail(source: source, book: try XCTUnwrap(books.first)))
        let chapters = try unwrap(await engine.getChapterList(source: source, book: detail))
        _ = try unwrap(await engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))

        XCTAssertEqual(network.requestedURLs, [searchURL, bookURL, tocURL, chapterURL])
        for request in network.requests.dropFirst() {
            XCTAssertEqual(header("X-Nonce", in: request), "fixture-nonce")
            XCTAssertEqual(header("Cookie", in: request), "sid=fixture")
        }
    }

    func testJavaImporterFixtureCreatesArrayListAndSupportsMessageDigest() async throws {
        let source = try loadFixture(named: "legado-java-import-source")
        let searchURL = "https://fixture.example/java-import/search?q=swift"
        let chapterURL = "https://fixture.example/java-import/chapter/1"
        let network = CorpusNetworkClient(responses: [
            searchURL: .init(body: #"{"ok":true}"#),
            chapterURL: .init(body: "<html><body><article>Java 正文</article></body></html>")
        ])
        let engine = LegadoSourceEngine(network: network)

        let books = try unwrap(await engine.searchBooks(source: source, keyword: "swift", page: 1))
        XCTAssertEqual(books.map(\.name), ["Imported"])
        XCTAssertEqual(books.first?.bookUrl, "https://fixture.example/java-import/book")
        let chapter = BookChapter(title: "第一章", url: chapterURL, bookUrl: books[0].bookUrl, index: 0, isVip: false)
        let content = try unwrap(await engine.getContent(source: source, chapter: chapter))
        XCTAssertEqual(content.paragraphs, ["Java 正文"])
    }

    func testCryptoFixtureBodyJsDecodesBase64JSONBeforeContentExtraction() async throws {
        let source = try loadFixture(named: "legado-crypto-source")
        let searchURL = "https://fixture.example/crypto/search?q=swift"
        let chapterURL = "https://fixture.example/crypto/chapter/1"
        let encoded = Data(#"{"content":"Crypto 正文"}"#.utf8).base64EncodedString()
        let network = CorpusNetworkClient(responses: [
            searchURL: .init(body: #"{"books":[{"name":"Crypto Reader","url":"/crypto/book/1"}]}"#),
            chapterURL: .init(body: encoded, contentType: "text/plain")
        ])
        let engine = LegadoSourceEngine(network: network)

        let books = try unwrap(await engine.searchBooks(source: source, keyword: "swift", page: 1))
        let chapter = BookChapter(title: "第一章", url: chapterURL, bookUrl: books[0].bookUrl, index: 0, isVip: false)
        let content = try unwrap(await engine.getContent(source: source, chapter: chapter))
        XCTAssertEqual(content.paragraphs, ["Crypto 正文"])
    }

    func testPipelineBatchReportIncludesRedactedRequestResponseEvidence() async throws {
        let source = try loadFixture(named: "legado-mixed-response-source")
        let searchURL = "https://fixture.example/mixed/search?q=%E6%B7%B7%E5%90%88"
        let bookURL = "https://fixture.example/mixed/book/1"
        let tocURL = "https://fixture.example/mixed/toc/1"
        let chapterURL = "https://fixture.example/mixed/chapter/1"
        let network = CorpusNetworkClient(responses: [
            searchURL: .init(body: "\u{FEFF})]}',<pre>prefix {\"data\":{\"items\":[{\"title\":\"混合书\",\"author\":\"Fixture\",\"url\":\"/mixed/book/1\"}]}}</pre>", contentType: "text/html", setCookie: "sid=secret; Path=/"),
            bookURL: .init(body: "\u{FEFF}<pre>prefix {\"title\":\"混合书\",\"toc\":\"/mixed/toc/1\"}</pre>", contentType: "text/html"),
            tocURL: .init(body: "\u{FEFF}<pre>prefix {\"chapters\":[{\"title\":\"第一章\",\"url\":\"/mixed/chapter/1\"}]}</pre>", contentType: "text/html"),
            chapterURL: .init(body: "\u{FEFF}<pre>prefix {\"content\":\"混合正文\"}</pre>", contentType: "text/html")
        ])
        let engine = LegadoSourceEngine(network: network)

        let report = await SourceBatchDiagnosticRunner(engine: engine).run(
            source: source, keyword: "混合", deepCheck: true, timeout: 1
        )

        XCTAssertEqual(report.steps.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertEqual(report.steps.first?.requestMethod, "GET")
        XCTAssertEqual(report.steps.first?.responseStatusCode, 200)
        XCTAssertEqual(report.steps.first?.responseHeaders?["Content-Type"], "text/html")
        XCTAssertTrue(report.steps.first?.cookieSummary?.contains("sid=<redacted>") == true)
        XCTAssertEqual(report.steps.first?.finalURL, searchURL)
        let batch = SourceDiagnosticBatchReport(
            startedAt: report.startedAt,
            keyword: report.keyword,
            reports: [report]
        )
        let json = String(data: try batch.exportJSON(), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("sid=secret"))
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
            XCTFail("Legado corpus fixture failed: \(error)", file: file, line: line)
            throw error
        }
    }

    private func header(_ name: String, in request: SourceRequest) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private final class CorpusNetworkClient: SourceNetworkClient, @unchecked Sendable {
    struct Payload: Sendable {
        let body: String
        var contentType = "application/json"
        var setCookie: String?
    }

    private let responses: [String: Payload]
    private let lock = NSLock()
    private var recordedRequests: [SourceRequest] = []

    init(responses: [String: Payload]) { self.responses = responses }

    var requests: [SourceRequest] {
        lock.lock(); defer { lock.unlock() }
        return recordedRequests
    }

    var requestedURLs: [String] { requests.map { $0.url.absoluteString } }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lock.lock(); recordedRequests.append(request); lock.unlock()
        guard let payload = responses[request.url.absoluteString] else {
            return .failure(.network("fixture response missing for \(request.url.absoluteString)"))
        }
        var headers = ["Content-Type": payload.contentType]
        if let setCookie = payload.setCookie { headers["Set-Cookie"] = setCookie }
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: headers,
            body: payload.body,
            data: Data(payload.body.utf8)
        ))
    }
}
