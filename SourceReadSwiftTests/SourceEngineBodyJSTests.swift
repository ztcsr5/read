import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceEngineBodyJSTests: XCTestCase {
    func testContentAppliesBodyJsBeforeParsing() async throws {
        let source = BookSource(
            bookSourceName: "BodyJS",
            bookSourceUrl: "https://source.example.com",
            ruleContent: SourceRule(fields: ["content": "#content@text"]),
            raw: [
                "bodyJs": "result.replace('ENCODED_TEXT', '正文第一段')"
            ]
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://source.example.com/chapter/1",
            bookUrl: "https://source.example.com/book",
            index: 0,
            isVip: false
        )
        let network = StaticSourceNetworkClient(body: "<html><body><div id='content'>ENCODED_TEXT</div></body></html>")
        let engine = LegadoSourceEngine(network: network)

        let result = await engine.getContent(source: source, chapter: chapter)

        guard case .success(let content) = result else {
            return XCTFail("expected content")
        }
        XCTAssertEqual(content.paragraphs, ["正文第一段"])
    }

    func testContentAppliesBodyJsWithTopLevelReturn() async throws {
        let source = BookSource(
            bookSourceName: "BodyJS",
            bookSourceUrl: "https://source.example.com",
            ruleContent: SourceRule(fields: ["content": "#content@text"]),
            customConfig: #"{"bodyjs":"return result.replace('A', 'B')"}"#
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://source.example.com/chapter/1",
            bookUrl: "https://source.example.com/book",
            index: 0,
            isVip: false
        )
        let network = StaticSourceNetworkClient(body: "<html><body><div id='content'>A</div></body></html>")
        let engine = LegadoSourceEngine(network: network)

        let result = await engine.getContent(source: source, chapter: chapter)

        guard case .success(let content) = result else {
            return XCTFail("expected content")
        }
        XCTAssertEqual(content.paragraphs, ["B"])
    }

    func testContentAppliesBodyJsWithSourceVariable() async throws {
        let source = BookSource(
            bookSourceName: "BodyJSWithSource",
            bookSourceUrl: "https://source.example.com",
            ruleContent: SourceRule(fields: ["content": "#content@text"]),
            raw: [
                "bodyJs": "var name = source.sourceName; return result.replace('A', name);"
            ]
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://source.example.com/chapter/1",
            bookUrl: "https://source.example.com/book",
            index: 0,
            isVip: false
        )
        let network = StaticSourceNetworkClient(body: "<html><body><div id='content'>A</div></body></html>")
        let engine = LegadoSourceEngine(network: network)

        let result = await engine.getContent(source: source, chapter: chapter)

        guard case .success(let content) = result else {
            return XCTFail("expected content")
        }
        XCTAssertEqual(content.paragraphs, ["BodyJSWithSource"])
    }

    func testChapterListUsesBookDetailTocUrlWhenPresent() async throws {
        let source = BookSource(
            bookSourceName: "TOC URL",
            bookSourceUrl: "https://source.example.com",
            ruleToc: SourceRule(fields: [
                "chapterList": ".chapter",
                "chapterName": "a@text",
                "chapterUrl": "a@href"
            ])
        )
        let detail = BookDetail(
            name: "书名",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://source.example.com/book/1",
            tocUrl: "https://source.example.com/book/1/catalog",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil,
            latestChapter: nil
        )
        let network = RecordingSourceNetworkClient(
            responses: [
                "https://source.example.com/book/1/catalog": "<html><body><div class='chapter'><a href='/chapter/1'>第一章</a></div></body></html>"
            ]
        )
        let engine = LegadoSourceEngine(network: network)

        let result = await engine.getChapterList(source: source, book: detail)

        guard case .success(let chapters) = result else {
            return XCTFail("expected chapters")
        }
        XCTAssertEqual(network.requestedURLs, ["https://source.example.com/book/1/catalog"])
        XCTAssertEqual(chapters.first?.title, "第一章")
        XCTAssertEqual(chapters.first?.url, "https://source.example.com/chapter/1")
    }
    func testContentFollowsNextContentPages() async throws {
        let source = BookSource(
            bookSourceName: "PagedContent",
            bookSourceUrl: "https://source.example.com",
            ruleContent: SourceRule(fields: [
                "content": "#content@text",
                "nextContentUrl": "a.next@href"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://source.example.com/chapter/1",
            bookUrl: "https://source.example.com/book",
            index: 0,
            isVip: false
        )
        let network = RecordingSourceNetworkClient(
            responses: [
                "https://source.example.com/chapter/1": "<html><body><div id='content'>page one</div><a class='next' href='/chapter/1-2'>next</a></body></html>",
                "https://source.example.com/chapter/1-2": "<html><body><div id='content'>page two</div></body></html>"
            ]
        )
        let engine = LegadoSourceEngine(network: network)

        let result = await engine.getContent(source: source, chapter: chapter)

        guard case .success(let content) = result else {
            return XCTFail("expected content")
        }
        XCTAssertEqual(network.requestedURLs, [
            "https://source.example.com/chapter/1",
            "https://source.example.com/chapter/1-2"
        ])
        XCTAssertEqual(content.paragraphs, ["page one", "page two"])
        XCTAssertNil(content.nextContentUrl)
    }

    func testChapterListFollowsNextTocPages() async throws {
        let source = BookSource(
            bookSourceName: "PagedTOC",
            bookSourceUrl: "https://source.example.com",
            ruleToc: SourceRule(fields: [
                "chapterList": ".chapter",
                "chapterName": "a@text",
                "chapterUrl": "a@href",
                "nextTocUrl": "a.next@href"
            ])
        )
        let detail = BookDetail(
            name: "Book",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://source.example.com/book/1",
            tocUrl: "https://source.example.com/book/1/catalog",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil,
            latestChapter: nil
        )
        let network = RecordingSourceNetworkClient(
            responses: [
                "https://source.example.com/book/1/catalog": "<html><body><div class='chapter'><a href='/c/1'>One</a></div><a class='next' href='/book/1/catalog-2'>next</a></body></html>",
                "https://source.example.com/book/1/catalog-2": "<html><body><div class='chapter'><a href='/c/2'>Two</a></div></body></html>"
            ]
        )
        let engine = LegadoSourceEngine(network: network)

        let result = await engine.getChapterList(source: source, book: detail)

        guard case .success(let chapters) = result else {
            return XCTFail("expected chapters")
        }
        XCTAssertEqual(network.requestedURLs, [
            "https://source.example.com/book/1/catalog",
            "https://source.example.com/book/1/catalog-2"
        ])
        XCTAssertEqual(chapters.map(\.title), ["One", "Two"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        XCTAssertEqual(chapters.map(\.url), [
            "https://source.example.com/c/1",
            "https://source.example.com/c/2"
        ])
    }
}

private final class StaticSourceNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let body: String

    init(body: String) {
        self.body = body
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: [:],
            body: body,
            data: Data(body.utf8)
        ))
    }
}

private final class RecordingSourceNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let responses: [String: String]
    private let lock = NSLock()
    private var urls: [String] = []

    var requestedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    init(responses: [String: String]) {
        self.responses = responses
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let urlText = request.url.absoluteString
        lock.lock()
        urls.append(urlText)
        lock.unlock()

        let body = responses[urlText] ?? ""
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: [:],
            body: body,
            data: Data(body.utf8)
        ))
    }
}
