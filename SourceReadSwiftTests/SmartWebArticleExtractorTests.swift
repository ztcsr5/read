import XCTest
@testable import SourceReadSwift

final class SmartWebArticleExtractorTests: XCTestCase {
    func testRemovesBoilerplateAndKeepsArticleText() {
        let html = """
        <html><head><title>测试文章</title><style>.ad{}</style></head>
        <body><nav>首页 登录</nav><main><h1>测试文章</h1><p>第一段正文。</p><p>第二段正文。</p></main><script>alert(1)</script></body></html>
        """
        let article = SmartWebArticleExtractor.extract(html: html)
        XCTAssertEqual(article.title, "测试文章")
        XCTAssertTrue(article.text.contains("第一段正文"))
        XCTAssertFalse(article.text.contains("首页"))
        XCTAssertEqual(article.paragraphs.filter { $0 == "第一段正文。" }.count, 1)
    }

    func testMalformedHTMLStillProducesText() {
        let article = SmartWebArticleExtractor.extract(html: "正文一\n\n正文二", fallbackTitle: "Fallback")
        XCTAssertEqual(article.title, "Fallback")
        XCTAssertEqual(article.paragraphs, ["正文一", "正文二"])
    }
}
