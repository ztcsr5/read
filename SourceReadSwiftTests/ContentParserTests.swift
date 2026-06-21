import XCTest
@testable import SourceReadSwift

final class ContentParserTests: XCTestCase {
    func testHTMLContentSplitsParagraphTags() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>第一段</p><p>第二段<br>第三段</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["第一段", "第二段", "第三段"])
    }
}
