import Foundation

/// A deterministic Search → Detail → TOC → Content execution result.
///
/// The UI used to duplicate this chain in three different screens.  Keeping
/// the chain in one value type gives source diagnostics, rule previews and the
/// reader the same stage ordering and error semantics.  A successful prefix is
/// retained when a later stage fails so callers can show actionable evidence
/// instead of losing the useful part of the run.
struct SourcePipelineResult: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceName: String
    let sourceURL: String
    let keyword: String
    let startedAt: Date
    let searchBooks: [SearchBook]
    let detail: BookDetail?
    let chapters: [BookChapter]
    let content: ChapterContent?
    let steps: [SourceDiagnosticStep]

    init(
        id: UUID = UUID(),
        sourceName: String,
        sourceURL: String,
        keyword: String,
        startedAt: Date = Date(),
        searchBooks: [SearchBook] = [],
        detail: BookDetail? = nil,
        chapters: [BookChapter] = [],
        content: ChapterContent? = nil,
        steps: [SourceDiagnosticStep] = []
    ) {
        self.id = id
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.keyword = keyword
        self.startedAt = startedAt
        self.searchBooks = searchBooks
        self.detail = detail
        self.chapters = chapters
        self.content = content
        self.steps = steps.sorted { lhs, rhs in
            guard let left = SourceDiagnosticStage.allCases.firstIndex(of: lhs.stage),
                  let right = SourceDiagnosticStage.allCases.firstIndex(of: rhs.stage) else { return false }
            return left < right
        }
    }

    var report: SourceDiagnosticReport {
        SourceDiagnosticReport(
            sourceName: sourceName,
            sourceURL: sourceURL,
            keyword: keyword,
            startedAt: startedAt,
            steps: steps
        )
    }

    var overallStatus: SourceHealthStatus { report.overallStatus }
    var isComplete: Bool {
        content != nil && chapters.isEmpty == false && detail != nil && searchBooks.isEmpty == false
    }
}

/// The diagnostic-friendly form of a pipeline run. Unlike `Result`, this keeps
/// the successful prefix and every stage observation when a later stage fails.
struct SourcePipelineExecution: Sendable {
    let result: SourcePipelineResult
    let error: SourceEngineError?

    var isSuccess: Bool { error == nil }
}

extension SourceEngine {
    /// Runs the complete source chain with bounded per-stage timeouts.
    ///
    /// This is intentionally a protocol extension instead of a second engine:
    /// test doubles and future engines automatically get the same pipeline
    /// contract.  The first failure is returned with its diagnostic report in
    /// `SourcePipelineExecution`, while successful prefixes remain available to
    /// callers through the failure payload.
    func runPipelineExecution(
        source: BookSource,
        keyword: String,
        page: Int = 1,
        timeout: TimeInterval = 20
    ) async -> SourcePipelineExecution {
        let startedAt = Date()
        let cleanKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKeyword.isEmpty else {
            return SourcePipelineExecution(
                result: SourcePipelineResult(
                    sourceName: source.bookSourceName,
                    sourceURL: source.bookSourceUrl,
                    keyword: cleanKeyword,
                    startedAt: startedAt
                ),
                error: .invalidSource("测试关键词为空")
            )
        }

        var steps: [SourceDiagnosticStep] = []
        var searched: [SearchBook] = []
        var detail: BookDetail?
        var chapters: [BookChapter] = []
        var content: ChapterContent?

        func elapsed(_ start: Date) -> Int {
            max(0, Int(Date().timeIntervalSince(start) * 1_000))
        }

        func makeResult() -> SourcePipelineResult {
            SourcePipelineResult(
                sourceName: source.bookSourceName,
                sourceURL: source.bookSourceUrl,
                keyword: cleanKeyword,
                startedAt: startedAt,
                searchBooks: searched,
                detail: detail,
                chapters: chapters,
                content: content,
                steps: steps
            )
        }

        func failure(_ error: SourceEngineError, stage: SourceDiagnosticStage, start: Date, count: Int = 0) -> SourcePipelineExecution {
            let message = error.displayMessage
            steps.append(SourceDiagnosticStep(
                stage: stage,
                status: SourceDiagnosticClassifier.status(message: message, stage: stage.rawValue, resultCount: count),
                requestSummary: stage == .search ? "keyword=\(cleanKeyword)&page=\(page)" : nil,
                responseSummary: message,
                matchCount: count,
                elapsedMilliseconds: elapsed(start),
                failureClassification: String(describing: error),
                failureCode: SourceDiagnosticClassifier.kind(error: error, stage: stage.rawValue)
            ))
            return SourcePipelineExecution(result: makeResult(), error: error)
        }

        let searchStarted = Date()
        let search = await withTimeout(seconds: timeout) { await self.searchBooks(source: source, keyword: cleanKeyword, page: page) }
            ?? .failure(.network("搜索超时（超过 \(Int(timeout)) 秒）"))
        switch search {
        case .failure(let error):
            return failure(error, stage: .search, start: searchStarted)
        case .success(let books):
            searched = books
            if books.isEmpty {
                return failure(.empty("搜索结果为空"), stage: .search, start: searchStarted)
            }
            steps.append(SourceDiagnosticStep(
                stage: .search,
                status: .passed,
                requestSummary: "keyword=\(cleanKeyword)&page=\(page)",
                responseSummary: "搜索结果 \(books.count) 条",
                matchCount: books.count,
                elapsedMilliseconds: elapsed(searchStarted),
                failureClassification: nil,
                failureCode: nil
            ))
            guard let first = books.first else { return failure(.empty("搜索结果为空"), stage: .search, start: searchStarted) }

            let detailStarted = Date()
            let detailResult = await withTimeout(seconds: timeout) { await self.getBookDetail(source: source, book: first) }
                ?? .failure(.network("详情超时（超过 \(Int(timeout)) 秒）"))
            switch detailResult {
            case .failure(let error):
                return failure(error, stage: .detail, start: detailStarted, count: 0)
            case .success(let value):
                detail = value
                steps.append(SourceDiagnosticStep(
                    stage: .detail,
                    status: .passed,
                    requestSummary: value.bookUrl,
                    responseSummary: "详情：\(value.name)",
                    matchCount: 1,
                    elapsedMilliseconds: elapsed(detailStarted)
                ))
            }
        }

        guard let detail else {
            return SourcePipelineExecution(result: makeResult(), error: .empty("详情结果为空"))
        }
        let tocStarted = Date()
        let tocResult = await withTimeout(seconds: timeout) { await self.getChapterList(source: source, book: detail) }
            ?? .failure(.network("目录超时（超过 \(Int(timeout)) 秒）"))
        switch tocResult {
        case .failure(let error):
            return failure(error, stage: .toc, start: tocStarted)
        case .success(let value):
            chapters = value
            if value.isEmpty {
                return failure(.empty("目录为空"), stage: .toc, start: tocStarted)
            }
            steps.append(SourceDiagnosticStep(
                stage: .toc,
                status: .passed,
                requestSummary: detail.tocUrl ?? detail.bookUrl,
                responseSummary: "目录 \(value.count) 章",
                matchCount: value.count,
                elapsedMilliseconds: elapsed(tocStarted),
                failureClassification: nil
            ))
        }

        guard let firstChapter = chapters.first else {
            return SourcePipelineExecution(result: makeResult(), error: .empty("目录为空"))
        }
        let contentStarted = Date()
        let contentResult = await withTimeout(seconds: timeout) { await self.getContent(source: source, chapter: firstChapter) }
            ?? .failure(.network("正文超时（超过 \(Int(timeout)) 秒）"))
        switch contentResult {
        case .failure(let error):
            return failure(error, stage: .content, start: contentStarted, count: 0)
        case .success(let value):
            content = value
            steps.append(SourceDiagnosticStep(
                stage: .content,
                status: value.paragraphs.isEmpty ? .warning : .passed,
                requestSummary: firstChapter.url,
                responseSummary: "正文 \(value.paragraphs.count) 段",
                matchCount: value.paragraphs.count,
                elapsedMilliseconds: elapsed(contentStarted),
                failureClassification: value.paragraphs.isEmpty ? "empty-result" : nil,
                failureCode: value.paragraphs.isEmpty ? .emptyResult : nil
            ))
            return SourcePipelineExecution(result: makeResult(), error: nil)
        }
    }

    /// Runs the same chain while retaining partial diagnostics for UI and
    /// export. Use this when the caller needs to explain which stage failed.
    func runPipelineReport(
        source: BookSource,
        keyword: String,
        page: Int = 1,
        timeout: TimeInterval = 20
    ) async -> SourcePipelineExecution {
        await runPipelineExecution(source: source, keyword: keyword, page: page, timeout: timeout)
    }

    /// Compatibility wrapper for callers that only need a conventional
    /// success/failure result.
    func runPipeline(
        source: BookSource,
        keyword: String,
        page: Int = 1,
        timeout: TimeInterval = 20
    ) async -> Result<SourcePipelineResult, SourceEngineError> {
        let execution = await runPipelineExecution(source: source, keyword: keyword, page: page, timeout: timeout)
        if let error = execution.error { return .failure(error) }
        return .success(execution.result)
    }
}

private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async -> Result<T, SourceEngineError>) async -> Result<T, SourceEngineError>? {
    await withTaskGroup(of: Result<T, SourceEngineError>?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            if nanoseconds > 0 { try? await Task.sleep(nanoseconds: nanoseconds) }
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
