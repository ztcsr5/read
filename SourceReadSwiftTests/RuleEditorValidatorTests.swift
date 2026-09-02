import XCTest
@testable import SourceReadSwift

final class RuleEditorValidatorTests: XCTestCase {
    func testValidatesAndAppliesStructuredRuleDrafts() throws {
        let source = BookSource(
            bookSourceName: "Fixture",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{key}}",
            ruleSearch: SourceRule(fields: ["bookList": ".book"]),
            ruleContent: SourceRule(fields: ["content": "#content@text"])
        )
        let drafts = [
            "searchUrl": "https://example.com/search?q={{key}}",
            "ruleSearch": "{\"bookList\":\".result\",\"name\":\"h2\"}",
            "ruleContent": "#content@text"
        ]
        XCTAssertTrue(RuleEditorValidator().validate(source: source, drafts: drafts).isEmpty)

        let updated = source.updatingRules(
            searchURL: drafts["searchUrl"]!,
            search: drafts["ruleSearch"]!,
            detail: "",
            toc: "{\"chapterList\":\".chapter\"}",
            content: drafts["ruleContent"]!
        )
        XCTAssertEqual(updated.ruleSearch?.fields["bookList"], ".result")
        XCTAssertEqual(updated.ruleToc?.fields["chapterList"], ".chapter")
        XCTAssertEqual(updated.ruleContent?.raw, "#content@text")
    }

    func testReportsMalformedJSAndInvalidSearchURL() {
        let source = BookSource(
            bookSourceName: "Fixture",
            bookSourceUrl: "https://example.com"
        )
        let issues = RuleEditorValidator().validate(
            source: source,
            drafts: [
                "searchUrl": "not a url",
                "ruleSearch": "<js>return result"
            ]
        )
        XCTAssertTrue(issues.contains { $0.field == "searchUrl" })
        XCTAssertTrue(issues.contains { $0.field == "ruleSearch" })
    }
}
