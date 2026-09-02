import XCTest
@testable import SourceReadSwift

final class RulePreviewEvaluatorTests: XCTestCase {
    func testPreviewSelectsStageFieldFromJSONRuleObject() {
        let output = RulePreviewEvaluator().evaluate(
            sample: "<html><body><p class='content'>第一段</p><p class='content'>第二段</p></body></html>",
            ruleText: #"{"content":".content@text","replaceRegex":"广告"}"#,
            stage: .content
        )
        XCTAssertEqual(output, "第一段\n第二段")
    }

    func testPreviewSupportsJSONPathSample() {
        let output = RulePreviewEvaluator().evaluate(
            sample: #"{"items":[{"title":"One"},{"title":"Two"}]}"#,
            ruleText: #"{"bookList":"$.items[*].title"}"#,
            stage: .search
        )
        XCTAssertEqual(output, "One\nTwo")
    }

    func testPreviewReportsEmptyRule() {
        XCTAssertEqual(
            RulePreviewEvaluator().evaluate(sample: "<p>text</p>", ruleText: " ", stage: .detail),
            "规则为空"
        )
    }
}
