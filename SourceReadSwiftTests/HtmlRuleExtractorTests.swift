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

    func testXPathTextRuleJoinsMultipleValues() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div id="content">
            <p>Line A</p>
            <p>Line B</p>
          </div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: #"//div[@id="content"]/p/text()"#,
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(value, "Line A\nLine B")
    }

    func testXPathAttributeAndTextRulesInterleave() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="toc">
            <a href="/1">Chapter 1</a>
            <a href="/2">Chapter 2</a>
          </div>
        </body></html>
        """)

        let value = try HtmlRuleExtractor().value(
            from: document,
            rule: #"//div[@class="toc"]/a/@href%%//div[@class="toc"]/a/text()"#,
            baseUrl: URL(string: "https://example.com/book")!
        )

        XCTAssertEqual(value, "https://example.com/1\nChapter 1\nhttps://example.com/2\nChapter 2")
    }

    func testXPathPrefixAndCSSPrefixAreNormalized() throws {
        let document = try SwiftSoup.parse("""
        <html><body>
          <div class="book"><a href="/book/1">Book One</a></div>
        </body></html>
        """)

        let xpath = try HtmlRuleExtractor().value(
            from: document,
            rule: #"@XPath://div[@class="book"]/a/text()"#,
            baseUrl: URL(string: "https://example.com")!
        )
        let css = try HtmlRuleExtractor().value(
            from: document,
            rule: "@CSS:.book a@href",
            baseUrl: URL(string: "https://example.com")!
        )

        XCTAssertEqual(xpath, "Book One")
        XCTAssertEqual(css, "https://example.com/book/1")
    }

    func testXPathSelectorSupportsAttributeFiltersAndIndexes() throws {
        let html = """
        <html><body>
          <ul>
            <li data-id="1"><a href="/a">A</a></li>
            <li data-id="2"><a href="/b">B</a></li>
          </ul>
        </body></html>
        """

        let first = try HtmlRuleExtractor().select(
            html,
            baseUrl: URL(string: "https://example.com")!,
            listRule: #"//li[@data-id="2"]/a"#
        )
        let last = try HtmlRuleExtractor().select(
            html,
            baseUrl: URL(string: "https://example.com")!,
            listRule: "//li[last()]"
        )

        XCTAssertEqual(try first.map { try $0.text() }, ["B"])
        XCTAssertEqual(try last.map { try $0.text() }, ["B"])
    }
}
