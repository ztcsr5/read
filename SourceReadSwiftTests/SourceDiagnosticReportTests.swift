import XCTest
@testable import SourceReadSwift

final class SourceDiagnosticReportTests: XCTestCase {
    func testReportSortsStagesAndComputesWorstStatus() {
        let report = SourceDiagnosticReport(
            sourceName: "Fixture",
            sourceURL: "fixture://source",
            keyword: "测试",
            steps: [
                SourceDiagnosticStep(stage: .content, status: .passed, matchCount: 4),
                SourceDiagnosticStep(stage: .search, status: .passed, matchCount: 2),
                SourceDiagnosticStep(stage: .detail, status: .warning, responseSummary: "empty"),
                SourceDiagnosticStep(stage: .toc, status: .passed, matchCount: 1)
            ]
        )
        XCTAssertEqual(report.steps.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertEqual(report.overallStatus, .warning)
        XCTAssertEqual(report.firstFailure?.stage, .detail)
    }

    func testPrioritizedReportsPutFailuresBeforeWarningsAndPasses() {
        func report(_ status: SourceHealthStatus, name: String) -> SourceDiagnosticReport {
            SourceDiagnosticReport(
                sourceName: name,
                sourceURL: "fixture://\(name)",
                keyword: "k",
                steps: [SourceDiagnosticStep(stage: .search, status: status)]
            )
        }
        let ordered = SourceDiagnosticReport.prioritized([
            report(.passed, name: "pass"),
            report(.warning, name: "warn"),
            report(.failed, name: "fail")
        ])
        XCTAssertEqual(ordered.map(\.sourceName), ["fail", "warn", "pass"])
    }
}
