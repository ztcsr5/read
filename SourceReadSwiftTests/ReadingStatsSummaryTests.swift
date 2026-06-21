import XCTest
@testable import SourceReadSwift

final class ReadingStatsSummaryTests: XCTestCase {
    func testAggregatesReadingStatsFromBookshelfBooks() {
        let now = Date()
        let remote = BookshelfBook(
            id: "remote",
            title: "Remote Book",
            author: "A",
            coverURL: nil,
            sourceName: "Remote",
            sourceURL: "https://example.com",
            bookURL: "https://example.com/book",
            intro: nil,
            totalChapters: 10,
            currentChapterIndex: 4,
            bookmarks: [
                ReaderBookmark(chapterIndex: 1, chapterTitle: "One", snippet: "A"),
                ReaderBookmark(chapterIndex: 2, chapterTitle: "Two", snippet: "B")
            ],
            lastReadAt: now,
            readingSessionCount: 2,
            totalReadingSeconds: 600
        )
        let local = BookshelfBook(
            id: "local",
            title: "Local Book",
            author: "B",
            coverURL: nil,
            sourceName: "Local",
            sourceURL: "local://text",
            bookURL: "local",
            intro: nil,
            totalChapters: 4,
            currentChapterIndex: 1,
            bookmarks: [],
            lastReadAt: now.addingTimeInterval(-100),
            readingSessionCount: 1,
            totalReadingSeconds: 120
        )

        let summary = ReadingStatsSummary(books: [remote, local])

        XCTAssertEqual(summary.totalBooks, 2)
        XCTAssertEqual(summary.localBooks, 1)
        XCTAssertEqual(summary.remoteBooks, 1)
        XCTAssertEqual(summary.readBooks, 2)
        XCTAssertEqual(summary.bookmarkedBooks, 1)
        XCTAssertEqual(summary.totalBookmarks, 2)
        XCTAssertEqual(summary.totalSessions, 3)
        XCTAssertEqual(summary.totalReadingSeconds, 720)
        XCTAssertEqual(summary.averageProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.mostReadBook?.id, "remote")
        XCTAssertEqual(summary.recentBooks.map(\.id), ["remote", "local"])
    }

    func testEmptyStatsAreZero() {
        let summary = ReadingStatsSummary(books: [])

        XCTAssertEqual(summary.totalBooks, 0)
        XCTAssertEqual(summary.averageProgress, 0)
        XCTAssertNil(summary.mostReadBook)
        XCTAssertTrue(summary.recentBooks.isEmpty)
    }
}
