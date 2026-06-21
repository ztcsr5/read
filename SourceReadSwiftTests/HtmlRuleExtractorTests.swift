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
            rule: ".missing@href || .book .title@text",
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

    func testIndexedSelectorPicksRequestedElement() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <a class="chapter" href="/c/1">One</a>
          <a class="chapter" href="/c/2">Two</a>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".chapter@1@href",
            baseUrl: URL(string: "https://example.com/book")!
        )

        XCTAssertEqual(value, "https://example.com/c/2")
    }

    func testOwnTextAndTextNodesAreSupported() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="intro">Outer <span>Inner</span> Tail</div>
        </body></html>
        """)

        let ownText = try HtmlRuleExtractor().value(
            from: document,
            rule: ".intro@ownText",
            baseUrl: URL(string: "https://example.com")!
        )
        let textNodes = try HtmlRuleExtractor().value(
            from: document,
            rule: ".intro@textNodes",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(ownText, "Outer Tail")
        XCTAssertTrue(textNodes.contains("Outer"))
        XCTAssertTrue(textNodes.contains("Tail"))
    }

    func testAllAttributeJoinsMultipleElements() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <p>A</p>
          <p>B</p>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: "p@all",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "A\nB")
    }

    func testMergeOperatorInterleavesHTMLValues() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <a class="free" href="/1">第一章</a>
          <a class="free" href="/3">第三章</a>
          <a class="vip" href="/2">第二章</a>
          <a class="vip" href="/4">第四章</a>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: ".free@text%%.vip@text",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "第一章\n第二章\n第三章\n第四章")
    }

    func testMergeOperatorInterleavesHTMLNodes() throws {
        let html = """
        <html><body>
          <a class="free" href="/1">第一章</a>
          <a class="free" href="/3">第三章</a>
          <a class="vip" href="/2">第二章</a>
          <a class="vip" href="/4">第四章</a>
        </body></html>
        """

        let elements = try HtmlRuleExtractor().select(
            html,
            baseUrl: URL(string: "https://example.com")!,
            listRule: ".free%%.vip"
        )

        XCTAssertEqual(try elements.map { try $0.text() }, ["第一章", "第二章", "第三章", "第四章"])
    }

    func testListFallbackUsesFirstNonEmptySelector() throws {
        let html = """
        <html><body>
          <a class="book">Book</a>
        </body></html>
        """

        let elements = try HtmlRuleExtractor().select(
            html,
            baseUrl: URL(string: "https://example.com")!,
            listRule: ".missing || .book"
        )

        XCTAssertEqual(try elements.map { try $0.text() }, ["Book"])
    }

    func testFallbackOperatorIgnoresNestedCSSOperatorText() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <a data-key="Alpha || Beta">Primary</a>
          <span>Fallback</span>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: "a[data-key='Alpha || Beta']@text || span@text",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "Primary")
    }
}
