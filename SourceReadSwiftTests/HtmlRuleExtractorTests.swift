import XCTest
import SwiftSoup
@testable import SourceReadSwift

final class HtmlRuleExtractorTests: XCTestCase {
    func testValueUsesFirstNonEmptyAlternative() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book"><a class="title" href="/book/1">Title</a></div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".missing@text || .book .title@text",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "Title")
    }

    func testAlternativeURLAttributeIsAbsolutized() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book"><a class="title" href="/book/1">Title</a></div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".missing@href || .book .title@href",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "https://example.com/book/1")
    }

    func testRegexTransformCleansExtractedValue() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book"><a class="title">[完结] Title 最新章节</a></div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".book .title@text##\\[完结\\] ## ## 最新章节##",
            baseUrl: URL(string: "https://example.com/search")!
        )

        XCTAssertEqual(value, "Title")
    }
}
