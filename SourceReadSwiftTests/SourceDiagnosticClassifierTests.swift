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
}
