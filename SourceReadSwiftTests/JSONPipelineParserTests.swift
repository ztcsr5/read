import XCTest
@testable import SourceReadSwift

final class JSONPipelineParserTests: XCTestCase {
    func testParseJSONBookDetail() throws {
        let source = BookSource(
            bookSourceName: "API源",
            bookSourceUrl: "https://api.example.com",
            ruleBookInfo: SourceRule(fields: [
                "name": "data.name",
                "author": "data.author",
                "intro": "data.intro"
            ])
        )
        let book = SearchBook(
            name: "旧名",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://api.example.com/book/1",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil
        )
        let response = SourceResponse(
            url: URL(string: book.bookUrl)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"name":"斗破苍穹","author":"天蚕土豆","intro":"简介"}}"#,
            data: Data()
        )

        let result = BookDetailParser().parse(source: source, book: book, response: response)
        guard case .success(let detail) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(detail.name, "斗破苍穹")
        XCTAssertEqual(detail.author, "天蚕土豆")
    }

    func testParseJSONChapterList() throws {
        let source = BookSource(
            bookSourceName: "API源",
            bookSourceUrl: "https://api.example.com",
            ruleToc: SourceRule(fields: [
                "chapterList": "data.chapters",
                "chapterName": "title",
                "chapterUrl": "url"
            ])
        )
        let book = BookDetail(
            name: "斗破苍穹",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://api.example.com/book/1",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil,
            latestChapter: nil
        )
        let response = SourceResponse(
            url: URL(string: book.bookUrl)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"chapters":[{"title":"第一章","url":"/c/1"}]}}"#,
            data: Data()
        )

        let result = ChapterListParser().parse(source: source, book: book, response: response)
        guard case .success(let chapters) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(chapters.first?.title, "第一章")
        XCTAssertEqual(chapters.first?.url, "https://api.example.com/c/1")
    }

    func testParseJSONContent() throws {
        let source = BookSource(
            bookSourceName: "API源",
            bookSourceUrl: "https://api.example.com",
            ruleContent: SourceRule(fields: [
                "content": "data.content"
            ])
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://api.example.com/c/1",
            bookUrl: "https://api.example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"content":"第一段\n第二段"}}"#,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)
        guard case .success(let content) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(content.paragraphs, ["第一段", "第二段"])
    }
}
