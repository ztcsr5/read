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

    func testPreviewReturnsStructuredStageAndMatchCount() {
        let result = RulePreviewEvaluator().preview(
            sample: "<article><p>A</p><p>B</p></article>",
            ruleText: "article p@text",
            stage: .content
        )

        XCTAssertEqual(result.stage, .content)
        XCTAssertEqual(result.values, ["A", "B"])
        XCTAssertEqual(result.matchedCount, 2)
        XCTAssertTrue(result.hasMatches)
        XCTAssertEqual(result.message, "A\nB")
    }

    func testPreviewEvidenceCapturesNormalizationRequestAndParsedOutput() {
        let result = RulePreviewEvaluator().preview(
            sample: "\u{FEFF}{\"items\":[{\"title\":\"One\"},{\"title\":\"Two\"}]}",
            ruleText: #"{"bookList":"$.items[*].title"}"#,
            stage: .search,
            baseURL: URL(string: "https://fixture.example/search?q=book")
        )

        XCTAssertEqual(result.evidence.requestMethod, "LOCAL")
        XCTAssertEqual(result.evidence.requestURL, "https://fixture.example/search?q=book")
        XCTAssertEqual(result.evidence.format, "JSON")
        XCTAssertTrue(result.evidence.normalizationApplied)
        XCTAssertEqual(result.evidence.selectedRule, "$.items[*].title")
        XCTAssertEqual(result.evidence.parsedOutput, ["One", "Two"])
        XCTAssertEqual(result.evidence.outputByteCount, "One\nTwo".utf8.count)
        XCTAssertEqual(result.evidence.normalizedResponse.first, "{")
    }
}
