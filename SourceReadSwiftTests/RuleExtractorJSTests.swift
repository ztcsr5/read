import XCTest
@testable import SourceReadSwift
import SwiftSoup

final class RuleExtractorJSTests: XCTestCase {
    func testHtmlRuleExtractorEvaluatesJavaScriptRule() throws {
        let html = """
        <html><body>
          <div class="book">
            <span class="price">120元</span>
          </div>
        </body></html>
        """
        let document = try SwiftSoup.parse(html)
        let extractor = HtmlRuleExtractor()
        
        // 规则是一个以 @js: 开头的 JS 规则
        let rule = "@js: result.replace('元', '')"
        let val = try extractor.value(from: document.select(".price").first!, rule: rule)
        XCTAssertEqual(val, "120")
    }

    func testJSONRuleExtractorEvaluatesJavaScriptRule() throws {
        let jsonStr = #"{"name": "斗破苍穹", "tags": ["玄幻", "热血"]}"#
        let data = jsonStr.data(using: .utf8)!
        let object = try JSONSerialization.jsonObject(with: data)
        let extractor = JSONRuleExtractor()
        
        // 规则是一个 JS 规则
        let rule = "@js: result.tags.join('-')"
        let val = extractor.value(from: object, path: rule) as? String
        XCTAssertEqual(val, "玄幻-热血")
    }
}
