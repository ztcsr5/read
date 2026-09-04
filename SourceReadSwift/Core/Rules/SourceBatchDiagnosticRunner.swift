import Foundation

/// Executes source diagnostics through the same pipeline used by the reader.
///
/// The old Source Manager batch check compressed a deep check into one search
/// row and then appended a free-form string.  That made exported reports lose
/// the stage that actually failed.  This runner keeps one structured report
/// per source, including Search -> Detail -> TOC -> Content when deep checks
/// are enabled, while retaining a bounded fan-out for large source libraries.
struct SourceBatchDiagnosticRunner: Sendable {
    let engine: SourceEngine

    init(engine: SourceEngine) {
        self.engine = engine
    }

    /// Runs one source.  `deepCheck` uses the production four-stage pipeline;
    /// a shallow run intentionally records only Search for quick health scans.
    func run(
        source: BookSource,
        keyword: String,
        deepCheck: Bool,
        page: Int = 1,
        timeout: TimeInterval = 10
    ) async -> SourceDiagnosticReport {
        let startedAt = Date()
        let cleanKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKeyword.isEmpty else {
            return SourceDiagnosticReport(
                sourceName: source.bookSourceName,
                sourceURL: source.bookSourceUrl,
                keyword: cleanKeyword,
                startedAt: startedAt,
                steps: [SourceDiagnosticStep(
                    stage: .search,
                    status: .failed,
                    requestSummary: "keyword=",
                    responseSummary: "测试关键词为空",
                    failureClassification: "empty-keyword"
                )]
            )
        }

        if deepCheck {
            // The pipeline applies the timeout per stage.  Give the outer
            // guard enough room for all four stages plus a small scheduling
            // margin, so a slow source still returns a report instead of
            // disappearing from the batch.
            let outerTimeout = max(timeout * 4 + 1, 1)
            if let execution = await AsyncTimeout.run(seconds: outerTimeout, operation: {
                await self.engine.runPipelineReport(
                    source: source,
                    keyword: cleanKeyword,
                    page: page,
                    timeout: timeout
                )
            }) {
                return execution.result.report
            }

            return timeoutReport(
                source: source,
                keyword: cleanKeyword,
                startedAt: startedAt,
                message: "完整链路超时（超过 (Int(outerTimeout)) 秒）"
            )
        }

        let searchStarted = Date()
        let result = await AsyncTimeout.run(seconds: max(timeout, 0), operation: {
            await self.engine.searchBooks(source: source, keyword: cleanKeyword, page: page)
        }) ?? .failure(.network("搜索超时（超过 (Int(timeout)) 秒）"))
        let elapsed = max(0, Int(Date().timeIntervalSince(searchStarted) * 1_000))

        let step: SourceDiagnosticStep
        switch result {
        case .success(let books):
            let isEmpty = books.isEmpty
            step = SourceDiagnosticStep(
                stage: .search,
                status: isEmpty ? .warning : .passed,
                requestSummary: "keyword=(cleanKeyword)&page=(page)",
                responseSummary: isEmpty ? "搜索结果为空" : "搜索结果 (books.count) 条",
                matchCount: books.count,
                elapsedMilliseconds: elapsed,
                failureClassification: isEmpty ? "empty-result" : nil
            )
        case .failure(let error):
            step = SourceDiagnosticStep(
                stage: .search,
                status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "search"),
                requestSummary: "keyword=(cleanKeyword)&page=(page)",
                responseSummary: error.displayMessage,
                elapsedMilliseconds: elapsed,
                failureClassification: String(describing: error)
            )
        }

        return SourceDiagnosticReport(
            sourceName: source.bookSourceName,
            sourceURL: source.bookSourceUrl,
            keyword: cleanKeyword,
            startedAt: startedAt,
            steps: [step]
        )
    }

    /// Runs all sources in bounded batches.  The optional callback is invoked
    /// on each completed source and is intentionally async so SwiftUI callers
    /// can update progress without blocking network tasks.
    func run(
        sources: [BookSource],
        keyword: String,
        deepCheck: Bool,
        page: Int = 1,
        timeout: TimeInterval = 10,
        batchSize: Int = 4,
        progress: (@Sendable (Int, SourceDiagnosticReport) async -> Void)? = nil
    ) async -> SourceDiagnosticBatchReport {
        let startedAt = Date()
        guard !sources.isEmpty else {
            return SourceDiagnosticBatchReport(
                startedAt: startedAt,
                finishedAt: Date(),
                keyword: keyword,
                reports: []
            )
        }

        let size = max(batchSize, 1)
        var reports: [SourceDiagnosticReport] = []
        reports.reserveCapacity(sources.count)
        var completed = 0

        var start = 0
        while start < sources.count {
            if Task.isCancelled { break }
            let end = Swift.min(start + size, sources.count)
            let batch = Array(sources[start..<end])
            await withTaskGroup(of: SourceDiagnosticReport.self) { group in
                for source in batch {
                    group.addTask {
                        await self.run(
                            source: source,
                            keyword: keyword,
                            deepCheck: deepCheck,
                            page: page,
                            timeout: timeout
                        )
                    }
                }
                for await report in group {
                    reports.append(report)
                    completed += 1
                    await progress?(completed, report)
                }
            }
            start = end
        }

        return SourceDiagnosticBatchReport(
            startedAt: startedAt,
            finishedAt: Date(),
            keyword: keyword,
            reports: reports
        )
    }

    private func timeoutReport(
        source: BookSource,
        keyword: String,
        startedAt: Date,
        message: String
    ) -> SourceDiagnosticReport {
        SourceDiagnosticReport(
            sourceName: source.bookSourceName,
            sourceURL: source.bookSourceUrl,
            keyword: keyword,
            startedAt: startedAt,
            steps: [SourceDiagnosticStep(
                stage: .search,
                status: .warning,
                requestSummary: "keyword=(keyword)",
                responseSummary: message,
                failureClassification: "timeout"
            )]
        )
    }
}
