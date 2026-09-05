import XCTest
@testable import SourceReadSwift

@MainActor
final class RSSArticleStateStoreTests: XCTestCase {
    func testRestoresReadAndFavoriteSnapshot() {
        let suite = "RSSArticleStateStoreTests.restore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = RSSArticleStateStore(defaults: defaults)
        store.restore(RSSArticleStateSnapshot(readIDs: ["read"], favoriteIDs: ["favorite"]))
        XCTAssertEqual(store.readIDs, Set(["read"]))
        XCTAssertEqual(store.favoriteIDs, Set(["favorite"]))
        let reloaded = RSSArticleStateStore(defaults: defaults)
        XCTAssertEqual(reloaded.readIDs, Set(["read"]))
        XCTAssertEqual(reloaded.favoriteIDs, Set(["favorite"]))
        defaults.removePersistentDomain(forName: suite)
    }

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

    func testPersistsAndClearsParagraphPosition() {
        let suite = "RSSArticleStateStoreTests.position.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let article = RSSArticlePreview(title: "A", link: "https://example.com/a", pubDate: nil, description: nil, sourceURL: "https://feed.one")
        let store = RSSArticleStateStore(defaults: defaults)
        store.updateParagraphPosition(7, for: article)
        XCTAssertEqual(store.paragraphPosition(for: article), 7)
        let reloaded = RSSArticleStateStore(defaults: defaults)
        XCTAssertEqual(reloaded.paragraphPosition(for: article), 7)
        store.clear(sourceURL: "https://feed.one")
        XCTAssertNil(store.paragraphPosition(for: article))
        defaults.removePersistentDomain(forName: suite)
    }
}
