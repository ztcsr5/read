import Foundation
import XCTest
@testable import SourceReadSwift

final class RuleEditorRoundTripTests: XCTestCase {
    func testFourStageDraftsRoundTripThroughBookSourceJSON() throws {
        let source = BookSource(
            bookSourceName: "Editor fixture",
            bookSourceUrl: "https://fixture.example",
            searchUrl: "https://fixture.example/search?q={{key}}",
            ruleSearch: SourceRule(fields: ["bookList": ".book", "name": "h2@text"]),
            ruleBookInfo: SourceRule(fields: ["name": "h1@text", "tocUrl": "a.toc@href"]),
            ruleToc: SourceRule(fields: ["chapterList": ".chapter", "chapterName": "a@text"]),
            ruleContent: SourceRule(raw: "@js: result.replace('A', 'B')")
        )

        let drafts = [
            "searchUrl": "https://fixture.example/search?q={{key}}",
            "ruleSearch": #"{"bookList":".result","name":"h2@text","bookUrl":"a@href"}"#,
            "ruleBookInfo": #"{"name":"h1@text","tocUrl":"a.toc@href"}"#,
            "ruleToc": #"{"chapterList":".chapter","chapterName":"a@text","chapterUrl":"a@href"}"#,
            "ruleContent": "@js: result.replace('A', 'B')"
        ]
        XCTAssertTrue(RuleEditorValidator().validate(source: source, drafts: drafts).isEmpty)

        let updated = source.updatingRules(
            searchURL: drafts["searchUrl"]!,
            search: drafts["ruleSearch"]!,
            detail: drafts["ruleBookInfo"]!,
            toc: drafts["ruleToc"]!,
            content: drafts["ruleContent"]!
        )
        let data = try JSONEncoder().encode(updated)
        let restored = try JSONDecoder().decode(BookSource.self, from: data)

        XCTAssertEqual(restored.searchUrl, drafts["searchUrl"])
        XCTAssertEqual(restored.ruleSearch?.fields["bookList"], ".result")
        XCTAssertEqual(restored.ruleBookInfo?.fields["tocUrl"], "a.toc@href")
        XCTAssertEqual(restored.ruleToc?.fields["chapterUrl"], "a@href")
        XCTAssertEqual(restored.ruleContent?.raw, drafts["ruleContent"])
    }

    func testPreviewEvaluatesSearchDetailTocAndContentStages() {
        let evaluator = RulePreviewEvaluator()
        XCTAssertEqual(
            evaluator.evaluate(
                sample: "<div class='book'><h2>书名</h2></div>",
                ruleText: #"{"bookList":".book","name":"h2@text"}"#,
                stage: .search
            ),
            "书名"
        )
        XCTAssertEqual(
            evaluator.evaluate(
                sample: "<h1>详情书名</h1>",
                ruleText: #"{"name":"h1@text"}"#,
                stage: .detail
            ),
            "详情书名"
        )
        XCTAssertEqual(
            evaluator.evaluate(
                sample: "<div class='chapter'><a href='/c/1'>第一章</a></div>",
                ruleText: #"{"chapterList":".chapter","chapterName":"a@text"}"#,
                stage: .toc
            ),
            "第一章"
        )
        XCTAssertEqual(
            evaluator.evaluate(
                sample: "<div id='content'>第一段<br>第二段</div>",
                ruleText: #"{"content":"#content@text"}"#,
                stage: .content
            ),
            "第一段 第二段"
        )
    }

    func testValidatorReportsMalformedRuleJSONAndJavaScriptSyntax() {
        let source = BookSource(bookSourceName: "Editor fixture", bookSourceUrl: "https://fixture.example")
        let issues = RuleEditorValidator().validate(source: source, drafts: [
            "ruleSearch": "{\"bookList\":",
            "ruleContent": "@js: function("
        ])
        XCTAssertTrue(issues.contains { $0.field == "ruleSearch" && $0.message.contains("JSON") })
        XCTAssertTrue(issues.contains { $0.field == "ruleContent" && $0.message.contains("JS") })
    }
}
