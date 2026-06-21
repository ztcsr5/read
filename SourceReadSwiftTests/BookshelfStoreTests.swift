import XCTest
@testable import SourceReadSwift

@MainActor
final class BookshelfStoreTests: XCTestCase {
    func testPersistsLocalTextBookContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))

        store.addLocalTextBook(
            LocalTextBook(
                title: "Local",
                author: "Local",
                chapters: [
                    LocalTextChapter(title: "Chapter 1", paragraphs: ["A", "B"], index: 0)
                ]
            )
        )

        let reloaded = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))
        XCTAssertEqual(reloaded.books.count, 1)
        XCTAssertEqual(reloaded.books.first?.title, "Local")
        XCTAssertEqual(reloaded.books.first?.localChapters?.first?.paragraphs, ["A", "B"])
        try? FileManager.default.removeItem(at: root)
    }

    func testTogglesBookmarks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))
        store.addLocalTextBook(
            LocalTextBook(
                title: "Local",
                author: "Local",
                chapters: [
                    LocalTextChapter(title: "Chapter 1", paragraphs: ["A"], index: 0)
                ]
            )
        )
        let id = try XCTUnwrap(store.books.first?.id)

        store.toggleBookmark(bookID: id, chapterIndex: 0, chapterTitle: "Chapter 1", snippet: "A")
        XCTAssertTrue(store.isBookmarked(bookID: id, chapterIndex: 0))

        store.toggleBookmark(bookID: id, chapterIndex: 0, chapterTitle: "Chapter 1", snippet: "A")
        XCTAssertFalse(store.isBookmarked(bookID: id, chapterIndex: 0))
        try? FileManager.default.removeItem(at: root)
    }

    func testMarksRefreshFailureWithoutOverwritingIntro() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))
        let book = SearchBook(
            name: "Remote",
            author: "Author",
            coverUrl: nil,
            bookUrl: "https://example.com/book",
            sourceName: "Example",
            sourceUrl: "https://example.com",
            intro: "Existing intro"
        )
        store.addOrUpdate(book)

        store.markRefreshFailure(bookID: book.id, message: "Failed")

        XCTAssertEqual(store.books.first?.intro, "Existing intro")
        try? FileManager.default.removeItem(at: root)
    }

    func testRecordsReadingSessionStats() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))
        store.addLocalTextBook(
            LocalTextBook(
                title: "Local",
                author: "Local",
                chapters: [
                    LocalTextChapter(title: "Chapter 1", paragraphs: ["A"], index: 0)
                ]
            )
        )
        let id = try XCTUnwrap(store.books.first?.id)

        store.markReaderOpened(bookID: id)
        store.recordReadingSession(bookID: id, duration: 125)

        let book = try XCTUnwrap(store.book(id: id))
        XCTAssertNotNil(book.lastOpenedAt)
        XCTAssertEqual(book.readingSessionCount, 1)
        XCTAssertEqual(book.totalReadingSeconds, 125)
        XCTAssertNotNil(book.lastReadAt)
        try? FileManager.default.removeItem(at: root)
    }

    func testSwitchSourceKeepsBookshelfIdentityAndResetsProgress() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))
        let original = SearchBook(
            name: "Book",
            author: "Author",
            coverUrl: nil,
            bookUrl: "https://old.example.com/book",
            sourceName: "Old",
            sourceUrl: "https://old.example.com",
            intro: "Old intro"
        )
        store.addOrUpdate(original)
        let bookID = original.id
        store.updateReadingProgress(bookID: bookID, chapterIndex: 8, chapterTitle: "Old 9", totalChapters: 20)
        store.toggleBookmark(bookID: bookID, chapterIndex: 8, chapterTitle: "Old 9", snippet: "Snippet")

        let replacement = SearchBook(
            name: "Book",
            author: "Author 2",
            coverUrl: "https://new.example.com/cover.jpg",
            bookUrl: "https://new.example.com/book",
            sourceName: "New",
            sourceUrl: "https://new.example.com",
            intro: "New intro"
        )
        store.switchSource(
            bookID: bookID,
            to: replacement,
            latestChapterTitle: "New Latest",
            intro: "Loaded intro",
            totalChapters: 30
        )

        let updated = try XCTUnwrap(store.book(id: bookID))
        XCTAssertEqual(updated.id, bookID)
        XCTAssertEqual(updated.sourceName, "New")
        XCTAssertEqual(updated.sourceURL, "https://new.example.com")
        XCTAssertEqual(updated.bookURL, "https://new.example.com/book")
        XCTAssertEqual(updated.currentChapterIndex, 0)
        XCTAssertEqual(updated.currentChapterTitle, nil)
        XCTAssertEqual(updated.totalChapters, 30)
        XCTAssertEqual(updated.latestChapterTitle, "New Latest")
        XCTAssertEqual(updated.intro, "Loaded intro")
        XCTAssertEqual(updated.bookmarks, nil)
        try? FileManager.default.removeItem(at: root)
    }
}
