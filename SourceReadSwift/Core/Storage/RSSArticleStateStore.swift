import Foundation
import Combine

@MainActor
final class RSSArticleStateStore: ObservableObject {
    @Published private(set) var readIDs: Set<String>
    @Published private(set) var favoriteIDs: Set<String>

    private let defaults: UserDefaults
    private let readKey = "rss.article.readIDs"
    private let favoriteKey = "rss.article.favoriteIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.readIDs = Set(defaults.stringArray(forKey: readKey) ?? [])
        self.favoriteIDs = Set(defaults.stringArray(forKey: favoriteKey) ?? [])
    }

    func isRead(_ article: RSSArticlePreview) -> Bool { readIDs.contains(article.id) }
    func isFavorite(_ article: RSSArticlePreview) -> Bool { favoriteIDs.contains(article.id) }

    func markRead(_ article: RSSArticlePreview) {
        readIDs.insert(article.id)
        persist()
    }

    func toggleFavorite(_ article: RSSArticlePreview) {
        if favoriteIDs.contains(article.id) {
            favoriteIDs.remove(article.id)
        } else {
            favoriteIDs.insert(article.id)
        }
        persist()
    }

    func clear(sourceURL: String? = nil) {
        if let sourceURL {
            let prefix = sourceURL + "|"
            readIDs = readIDs.filter { !$0.hasPrefix(prefix) }
            favoriteIDs = favoriteIDs.filter { !$0.hasPrefix(prefix) }
        } else {
            readIDs.removeAll()
            favoriteIDs.removeAll()
        }
        persist()
    }

    private func persist() {
        defaults.set(Array(readIDs), forKey: readKey)
        defaults.set(Array(favoriteIDs), forKey: favoriteKey)
    }
}
