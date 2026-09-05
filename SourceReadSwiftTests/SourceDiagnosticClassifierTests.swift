import XCTest
@testable import SourceReadSwift

final class SourceDiagnosticClassifierTests: XCTestCase {
    func testClassifiesVerificationAndLoginBeforeGenericFailure() {
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "Cloudflare challenge", stage: "search"), .verificationRequired)
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "HTTP 401 unauthorized", stage: "search"), .requiresLogin)
    }

    func testClassifiesBlockedAndEmptyResults() {
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "HTTP 403 Forbidden", stage: "search"), .blocked)
        XCTAssertEqual(SourceDiagnosticClassifier.status(message: "搜索结果为空", stage: "search", resultCount: 0), .warning)
    }

    func testProvidesStableFailureKindsAndRetryPolicy() {
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "HTTP 429 rate limit", stage: "search"), .blocked)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(message: "搜索超时", stage: "search"), .timeout)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(error: .rule("JSONPath 解析失败"), stage: "content"), .parsing)
        XCTAssertEqual(SourceDiagnosticClassifier.kind(error: .javascript("脚本异常"), stage: "search"), .javascript)
        XCTAssertTrue(SourceDiagnosticFailureKind.timeout.isRetryable)
        XCTAssertFalse(SourceDiagnosticFailureKind.parsing.isRetryable)
    }

    func testLegacyDiagnosticStepDefaultsFailureKindToNil() throws {
        let data = Data(#"{"stage":"search","status":"failed","matchCount":0}"#.utf8)
        let step = try JSONDecoder().decode(SourceDiagnosticStep.self, from: data)
        XCTAssertNil(step.failureCode)
        XCTAssertFalse(step.retryable)
    }
}
