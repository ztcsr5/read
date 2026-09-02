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

    func testTogglesParagraphBookmarksIndependently() throws {
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
        let id = try XCTUnwrap(store.books.first?.id)

        store.toggleBookmark(bookID: id, chapterIndex: 0, chapterTitle: "Chapter 1", paragraphIndex: 0, snippet: "A")
        store.toggleBookmark(bookID: id, chapterIndex: 0, chapterTitle: "Chapter 1", paragraphIndex: 1, snippet: "B")

        XCTAssertTrue(store.isBookmarked(bookID: id, chapterIndex: 0, paragraphIndex: 0))
        XCTAssertTrue(store.isBookmarked(bookID: id, chapterIndex: 0, paragraphIndex: 1))
        XCTAssertEqual(store.book(id: id)?.bookmarks?.count, 2)

        store.toggleBookmark(bookID: id, chapterIndex: 0, chapterTitle: "Chapter 1", paragraphIndex: 0, snippet: "A")

        XCTAssertFalse(store.isBookmarked(bookID: id, chapterIndex: 0, paragraphIndex: 0))
        XCTAssertTrue(store.isBookmarked(bookID: id, chapterIndex: 0, paragraphIndex: 1))
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

    func testPersistsParagraphReadingPosition() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = BookshelfPersistence(fileManager: .default, rootURL: root)
        let store = BookshelfStore(persistence: persistence)
        store.addLocalTextBook(
            LocalTextBook(
                title: "Local",
                author: "Local",
                chapters: [
                    LocalTextChapter(title: "Chapter 1", paragraphs: ["A", "B", "C"], index: 0)
                ]
            )
        )
        let id = try XCTUnwrap(store.books.first?.id)

        store.updateReadingProgress(
            bookID: id,
            chapterIndex: 0,
            chapterTitle: "Chapter 1",
            totalChapters: 1,
            paragraphIndex: 2
        )

        let reloaded = BookshelfStore(persistence: persistence)
        XCTAssertEqual(reloaded.book(id: id)?.currentParagraphIndex, 2)
        try? FileManager.default.removeItem(at: root)
    }

    func testLatestUpdatesTrackSeenChapterCount() throws {
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
            intro: nil
        )
        store.addOrUpdate(book)

        store.updateDetails(bookID: book.id, latestChapterTitle: "Chapter 10", intro: nil, totalChapters: 10)
        XCTAssertFalse(try XCTUnwrap(store.book(id: book.id)).hasUpdates)

        store.updateDetails(bookID: book.id, latestChapterTitle: "Chapter 12", intro: nil, totalChapters: 12)
        XCTAssertTrue(try XCTUnwrap(store.book(id: book.id)).hasUpdates)

        store.markUpdatesSeen(bookID: book.id)
        XCTAssertFalse(try XCTUnwrap(store.book(id: book.id)).hasUpdates)

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
        store.updateReadingProgress(bookID: bookID, chapterIndex: 8, chapterTitle: "Old 9", totalChapters: 20, paragraphIndex: 4)
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
        XCTAssertEqual(updated.currentParagraphIndex, nil)
        XCTAssertEqual(updated.totalChapters, 30)
        XCTAssertEqual(updated.seenTotalChapters, 30)
        XCTAssertEqual(updated.latestChapterTitle, "New Latest")
        XCTAssertEqual(updated.intro, "Loaded intro")
        XCTAssertEqual(updated.bookmarks, nil)
        try? FileManager.default.removeItem(at: root)
    }

    func testCreatesPersistsAndMovesBooksBetweenGroups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = BookshelfPersistence(fileManager: .default, rootURL: root)
        let groupPersistence = BookshelfGroupPersistence(fileManager: .default, rootURL: root)
        let store = BookshelfStore(persistence: persistence, groupPersistence: groupPersistence)
        let book = SearchBook(name: "Grouped", author: "Author", coverUrl: nil, bookUrl: "https://example.com/book", sourceName: "Example", sourceUrl: "https://example.com", intro: nil)
        store.addOrUpdate(book)
        store.createGroup(name: "待读")
        XCTAssertEqual(store.groups.count, 1)
        store.moveBooks(bookIDs: [book.id], toGroupName: "待读")
        XCTAssertEqual(store.book(id: book.id)?.groupName, "待读")

        let reloaded = BookshelfStore(persistence: persistence, groupPersistence: groupPersistence)
        XCTAssertEqual(reloaded.groups.first?.name, "待读")
        XCTAssertEqual(reloaded.book(id: book.id)?.groupName, "待读")
        store.deleteGroup(id: try XCTUnwrap(store.groups.first?.id))
        XCTAssertNil(store.book(id: book.id)?.groupName)
        try? FileManager.default.removeItem(at: root)
    }

    func testBackupRestoreRoundTripDropsUnknownGroupAssignments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = BookshelfPersistence(fileManager: .default, rootURL: root)
        let groupPersistence = BookshelfGroupPersistence(fileManager: .default, rootURL: root)
        let store = BookshelfStore(persistence: persistence, groupPersistence: groupPersistence)
        let book = SearchBook(name: "Backup", author: "Author", coverUrl: nil, bookUrl: "https://example.com/backup", sourceName: "Example", sourceUrl: "https://example.com", intro: nil)
        store.addOrUpdate(book)
        store.createGroup(name: "收藏")
        store.moveBooks(bookIDs: [book.id], toGroupName: "收藏")
        store.toggleBookmark(bookID: book.id, chapterIndex: 2, chapterTitle: "第三章", paragraphIndex: 4, snippet: "摘录")

        var snapshot = store.backupSnapshot()
        var modifiedBook = try XCTUnwrap(snapshot.books.first)
        modifiedBook.groupName = "不存在的分组"
        snapshot = BookshelfBackupSnapshot(books: [modifiedBook], groups: snapshot.groups)
        let restored = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root.appendingPathComponent("restored")), groupPersistence: BookshelfGroupPersistence(fileManager: .default, rootURL: root.appendingPathComponent("restored")))

        XCTAssertTrue(restored.restore(snapshot))
        XCTAssertEqual(restored.book(id: book.id)?.bookmarks?.first?.snippet, "摘录")
        XCTAssertNil(restored.book(id: book.id)?.groupName)
        XCTAssertEqual(restored.groups.first?.name, "收藏")
        try? FileManager.default.removeItem(at: root)
    }
}
