import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterContentCacheStoreTests: XCTestCase {
    func testPersistsChapterContentBySourceAndPurifySignature() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/chapter/1",
            bookUrl: "https://example.com/book",
            index: 0,
            isVip: false
        )
        let content = ChapterContent(
            chapter: chapter,
            title: "Chapter 1",
            paragraphs: ["A", "B"],
            nextContentUrl: nil
        )

        store.save(content, sourceURL: "https://source.example.com", purifyRules: ["广告.*##"])

        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertEqual(
            reloaded.content(
                sourceURL: "https://source.example.com",
                chapter: chapter,
                purifyRules: ["广告.*##"]
            )?.paragraphs,
            ["A", "B"]
        )
        XCTAssertNil(
            reloaded.content(
                sourceURL: "https://source.example.com",
                chapter: chapter,
                purifyRules: ["新的净化规则"]
            )
        )
        try? FileManager.default.removeItem(at: root)
    }

    func testRemoveAllPersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/chapter/1",
            bookUrl: "https://example.com/book",
            index: 0,
            isVip: false
        )
        store.save(
            ChapterContent(chapter: chapter, title: "Chapter 1", paragraphs: ["A"], nextContentUrl: nil),
            sourceURL: "https://source.example.com",
            purifyRules: []
        )

        store.removeAll()

        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertTrue(reloaded.entries.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    func testRemoveExpiredPersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ChapterContentCachePersistence(fileManager: .default, rootURL: root)
        try persistence.save([
            ChapterContentCacheEntry(
                key: "source|old",
                sourceURL: "source",
                chapterURL: "old",
                bookURL: "book",
                title: "Old",
                paragraphs: ["A"],
                nextContentUrl: nil,
                purifySignature: "",
                cachedAt: Date().addingTimeInterval(-40 * 24 * 60 * 60)
            ),
            ChapterContentCacheEntry(
                key: "source|new",
                sourceURL: "source",
                chapterURL: "new",
                bookURL: "book",
                title: "New",
                paragraphs: ["B"],
                nextContentUrl: nil,
                purifySignature: "",
                cachedAt: Date()
            )
        ])
        let store = ChapterContentCacheStore(persistence: persistence)

        store.removeExpired(olderThanDays: 30)

        XCTAssertEqual(store.entries.map(\.title), ["New"])
        let reloaded = ChapterContentCacheStore(persistence: persistence)
        XCTAssertEqual(reloaded.entries.map(\.title), ["New"])
        try? FileManager.default.removeItem(at: root)
    }
}
