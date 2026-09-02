import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterDownloadStoreTests: XCTestCase {
    func testDownloadRecordPersistsProgressAndResumesAsPaused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ChapterDownloadPersistence(fileManager: .default, rootURL: root)
        let store = ChapterDownloadStore(persistence: persistence)
        store.begin(bookID: "book", sourceURL: "source", bookURL: "book-url", title: "Book", chapterCount: 3)
        store.markRunning(bookID: "book")
        store.markCompleted(bookID: "book", chapterIndex: 1)

        let reloaded = ChapterDownloadStore(persistence: persistence)
        let record = try XCTUnwrap(reloaded.record(bookID: "book"))
        XCTAssertEqual(record.status, .paused)
        XCTAssertEqual(record.completedIndexes, [1])
        XCTAssertEqual(record.progress, 1.0 / 3.0, accuracy: 0.001)
        try? FileManager.default.removeItem(at: root)
    }

    func testFailedChapterIsRetriedAndClearedOnSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ChapterDownloadPersistence(fileManager: .default, rootURL: root)
        let store = ChapterDownloadStore(persistence: persistence)
        store.begin(bookID: "book", sourceURL: "source", bookURL: "book-url", title: "Book", chapterCount: 1)
        store.markFailed(bookID: "book", chapterIndex: 0, message: "timeout")
        store.markCompleted(bookID: "book", chapterIndex: 0)
        store.finish(bookID: "book")
        let record = try XCTUnwrap(store.record(bookID: "book"))
        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.failedIndexes, [])
        XCTAssertEqual(record.completedIndexes, [0])
        try? FileManager.default.removeItem(at: root)
    }

    func testCancelledDownloadKeepsRecordForExplicitResume() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ChapterDownloadPersistence(fileManager: .default, rootURL: root)
        let store = ChapterDownloadStore(persistence: persistence)
        store.begin(bookID: "book", sourceURL: "source", bookURL: "book-url", title: "Book", chapterCount: 2)
        store.markCompleted(bookID: "book", chapterIndex: 0)
        store.markCancelled(bookID: "book")
        XCTAssertEqual(store.record(bookID: "book")?.status, .cancelled)
        XCTAssertEqual(store.record(bookID: "book")?.completedIndexes, [0])
        try? FileManager.default.removeItem(at: root)
    }
}
