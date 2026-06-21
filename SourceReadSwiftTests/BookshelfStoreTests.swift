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
}
