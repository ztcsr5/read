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
