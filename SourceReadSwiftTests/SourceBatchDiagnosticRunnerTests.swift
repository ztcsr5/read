import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceBatchDiagnosticRunnerTests: XCTestCase {
    func testDeepRunExportsAllFourStagesInsteadOfACompressedDeepRow() async throws {
        let source = BookSource(bookSourceName: "Runner", bookSourceUrl: "https://fixture.example")
        let searchBook = SearchBook(
            name: "Book", author: "Author", coverUrl: nil,
            bookUrl: "https://fixture.example/book",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil
        )
        let detail = BookDetail(
            name: "Book", author: "Author", coverUrl: nil,
            bookUrl: searchBook.bookUrl, tocUrl: "https://fixture.example/toc",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl,
            intro: nil, latestChapter: nil
        )
        let chapter = BookChapter(
            title: "第一章", url: "https://fixture.example/chapter",
            bookUrl: detail.bookUrl, index: 0, isVip: false
        )
        let content = ChapterContent(
            chapter: chapter, title: chapter.title,
            paragraphs: ["正文"], nextContentUrl: nil
        )
        let engine = RunnerStubEngine(
            search: .success([searchBook]), detail: .success(detail),
            toc: .success([chapter]), content: .success(content)
        )

        let report = await SourceBatchDiagnosticRunner(engine: engine).run(
            source: source, keyword: "swift", deepCheck: true, timeout: 1
        )

        XCTAssertEqual(report.steps.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertEqual(report.steps.map(\.matchCount), [1, 1, 1, 1])
        XCTAssertEqual(report.overallStatus, .passed)
    }

    func testDeepRunRetainsSuccessfulPrefixWhenContentFails() async {
        let source = BookSource(bookSourceName: "Runner", bookSourceUrl: "https://fixture.example")
        let book = SearchBook(name: "Book", author: nil, coverUrl: nil, bookUrl: "https://fixture.example/book", sourceName: "Runner", sourceUrl: source.bookSourceUrl, intro: nil)
        let detail = BookDetail(name: "Book", author: nil, coverUrl: nil, bookUrl: book.bookUrl, tocUrl: nil, sourceName: "Runner", sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
        let chapter = BookChapter(title: "一", url: "https://fixture.example/chapter", bookUrl: book.bookUrl, index: 0, isVip: false)
        let engine = RunnerStubEngine(
            search: .success([book]), detail: .success(detail), toc: .success([chapter]),
            content: .failure(.rule("content mismatch"))
        )

        let report = await SourceBatchDiagnosticRunner(engine: engine).run(
            source: source, keyword: "book", deepCheck: true, timeout: 1
        )

        XCTAssertEqual(report.steps.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertEqual(report.steps.last?.status, .failed)
        XCTAssertEqual(report.firstFailure?.stage, .content)
    }

    func testBatchRunKeepsEverySourceReportAndProgressCount() async {
        let sources = (1...5).map { BookSource(bookSourceName: "Runner \($0)", bookSourceUrl: "https://fixture.example/\($0)") }
        let engine = RunnerStubEngine(
            search: .success([SearchBook(name: "Book", author: nil, coverUrl: nil, bookUrl: "https://fixture.example/book", sourceName: "Runner", sourceUrl: "https://fixture.example", intro: nil)]),
            detail: nil, toc: nil, content: nil
        )
        let progress = ProgressCounter()

        let report = await SourceBatchDiagnosticRunner(engine: engine).run(
            sources: sources, keyword: "swift", deepCheck: false,
            timeout: 1, batchSize: 2,
            progress: { count, _ in await progress.set(count) }
        )

        XCTAssertEqual(report.totalCount, sources.count)
        let completed = await progress.value
        XCTAssertEqual(completed, sources.count)
        XCTAssertTrue(report.reports.allSatisfy { $0.steps.count == 1 && $0.steps[0].stage == .search })
    }
}

private struct RunnerStubEngine: SourceEngine {
    let search: Result<[SearchBook], SourceEngineError>
    let detail: Result<BookDetail, SourceEngineError>?
    let toc: Result<[BookChapter], SourceEngineError>?
    let content: Result<ChapterContent, SourceEngineError>?

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { search }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { detail ?? .failure(.empty("detail missing")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { toc ?? .failure(.empty("toc missing")) }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> { content ?? .failure(.empty("content missing")) }
}

private actor ProgressCounter {
    private(set) var value = 0

    func set(_ value: Int) { self.value = value }
}
