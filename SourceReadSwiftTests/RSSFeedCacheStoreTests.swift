import XCTest
@testable import SourceReadSwift

@MainActor
final class RSSFeedCacheStoreTests: XCTestCase {
    func testPersistsAndReloadsArticles() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rss-cache-\(UUID().uuidString).json")
        let article = RSSArticlePreview(title: "Cached", link: "https://example.com/a", pubDate: nil, description: "body")
        let store = RSSFeedCacheStore(fileURL: url)
        store.save([article], sourceURL: "https://example.com/feed")

        let reloaded = RSSFeedCacheStore(fileURL: url)
        XCTAssertEqual(reloaded.articles(for: "https://example.com/feed")?.first?.title, "Cached")
        try? FileManager.default.removeItem(at: url)
    }

    func testRemoveIsScopedToSource() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rss-cache-\(UUID().uuidString).json")
        let store = RSSFeedCacheStore(fileURL: url)
        let a = RSSArticlePreview(title: "A", link: nil, pubDate: nil, description: nil)
        let b = RSSArticlePreview(title: "B", link: nil, pubDate: nil, description: nil)
        store.save([a], sourceURL: "one")
        store.save([b], sourceURL: "two")
        store.remove(sourceURL: "one")
        XCTAssertNil(store.articles(for: "one"))
        XCTAssertEqual(store.articles(for: "two")?.first?.title, "B")
        try? FileManager.default.removeItem(at: url)
    }
}
