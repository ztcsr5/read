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
}
