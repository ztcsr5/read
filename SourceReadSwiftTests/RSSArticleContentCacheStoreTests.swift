import XCTest
@testable import SourceReadSwift

@MainActor
final class RSSArticleContentCacheStoreTests: XCTestCase {
    func testPersistsAndReloadsArticleParagraphs() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rss-content-cache-\(UUID().uuidString).json")
        let article = RSSArticlePreview(title: "Article", link: "https://example.com/article", pubDate: nil, description: nil)
        let store = RSSArticleContentCacheStore(fileURL: url)
        store.save([" First ", "", "Second"], for: article)

        let reloaded = RSSArticleContentCacheStore(fileURL: url)
        XCTAssertEqual(reloaded.paragraphs(for: article), ["First", "Second"])
        XCTAssertNotNil(reloaded.cachedAt(for: article))
        try? FileManager.default.removeItem(at: url)
    }

    func testRemovesSingleArticleWithoutTouchingOtherEntries() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rss-content-cache-\(UUID().uuidString).json")
        let first = RSSArticlePreview(title: "First", link: "https://example.com/1", pubDate: nil, description: nil)
        let second = RSSArticlePreview(title: "Second", link: "https://example.com/2", pubDate: nil, description: nil)
        let store = RSSArticleContentCacheStore(fileURL: url)
        store.save(["One"], for: first)
        store.save(["Two"], for: second)

        store.remove(articleID: first.id)

        XCTAssertNil(store.paragraphs(for: first))
        XCTAssertEqual(store.paragraphs(for: second), ["Two"])
        try? FileManager.default.removeItem(at: url)
    }
}
