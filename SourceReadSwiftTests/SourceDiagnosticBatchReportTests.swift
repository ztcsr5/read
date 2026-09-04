import XCTest
@testable import SourceReadSwift

final class SourceDiagnosticBatchReportTests: XCTestCase {
    func testBatchReportPrioritizesFailuresAndRedactsCredentialMetadata() throws {
        let started = Date(timeIntervalSince1970: 1_000)
        let failed = SourceDiagnosticReport(
            sourceName: "Fixture Fail",
            sourceURL: "https://fixture.example/fail",
            keyword: "swift",
            startedAt: started,
            steps: [SourceDiagnosticStep(
                stage: .search,
                status: .failed,
                requestMethod: "POST",
                requestBody: "token=secret-value",
                requestHeaders: ["Authorization": "Bearer abc", "X-Test": "ok"],
                responseStatusCode: 401,
                responseHeaders: ["Set-Cookie": "sid=secret"],
                cookieSummary: "sid=secret; theme=dark",
                finalURL: "https://fixture.example/fail",
                retryCount: 1
            )]
        )
        let passed = SourceDiagnosticReport(
            sourceName: "Fixture Pass",
            sourceURL: "https://fixture.example/pass",
            keyword: "swift",
            startedAt: started,
            steps: [SourceDiagnosticStep(stage: .search, status: .passed, matchCount: 1)]
        )
        let report = SourceDiagnosticBatchReport(
            startedAt: started,
            finishedAt: started.addingTimeInterval(1.25),
            keyword: "swift",
            reports: [passed, failed]
        )

        XCTAssertEqual(report.reports.map(\.sourceName), ["Fixture Fail", "Fixture Pass"])
        XCTAssertEqual(report.elapsedMilliseconds, 1_250)
        XCTAssertEqual(report.failedCount, 1)
        let step = try XCTUnwrap(report.reports.first?.steps.first)
        XCTAssertEqual(step.requestHeaders?["Authorization"], "<redacted>")
        XCTAssertEqual(step.requestHeaders?["X-Test"], "ok")
        XCTAssertEqual(step.responseHeaders?["Set-Cookie"], "<redacted>")
        XCTAssertEqual(step.cookieSummary, "sid=<redacted>;theme=<redacted>")
        XCTAssertTrue(report.exportText().contains("HTTP 401"))

        let data = try report.exportJSON()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let jsonText = String(data: data, encoding: .utf8) ?? ""
        XCTAssertNotNil(json["reports"])
        XCTAssertFalse(jsonText.contains("Bearer abc"))
        XCTAssertFalse(jsonText.contains("secret"))
    }

    func testDiagnosticStepDecodesLegacyPayloadWithoutNewEvidenceFields() throws {
        let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","stage":"search","status":"passed","matchCount":2}"#.utf8)
        let step = try JSONDecoder().decode(SourceDiagnosticStep.self, from: data)
        XCTAssertEqual(step.stage, .search)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(step.matchCount, 2)
        XCTAssertNil(step.requestMethod)
        XCTAssertEqual(step.retryCount, 0)
    }
}
