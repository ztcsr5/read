import XCTest
@testable import SourceReadSwift

@MainActor
final class RSSArticleStateStoreTests: XCTestCase {
    func testReadAndFavoriteStatePersists() {
        let suite = "RSSArticleStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let article = RSSArticlePreview(title: "A", link: "https://example.com/a", pubDate: nil, description: nil)
        let store = RSSArticleStateStore(defaults: defaults)
        store.markRead(article)
        store.toggleFavorite(article)

        let reloaded = RSSArticleStateStore(defaults: defaults)
        XCTAssertTrue(reloaded.isRead(article))
        XCTAssertTrue(reloaded.isFavorite(article))
        defaults.removePersistentDomain(forName: suite)
    }

    func testClearsOnlyTheRequestedFeed() {
        let suite = "RSSArticleStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let first = RSSArticlePreview(title: "A", link: "https://example.com/a", pubDate: nil, description: nil, sourceURL: "https://feed.one")
        let second = RSSArticlePreview(title: "B", link: "https://example.com/b", pubDate: nil, description: nil, sourceURL: "https://feed.two")
        let store = RSSArticleStateStore(defaults: defaults)
        store.markRead(first)
        store.toggleFavorite(first)
        store.markRead(second)
        store.toggleFavorite(second)

        store.clear(sourceURL: "https://feed.one")

        XCTAssertFalse(store.isRead(first))
        XCTAssertFalse(store.isFavorite(first))
        XCTAssertTrue(store.isRead(second))
        XCTAssertTrue(store.isFavorite(second))
        defaults.removePersistentDomain(forName: suite)
    }
}
