import Foundation
import Combine

@MainActor
final class RSSArticleStateStore: ObservableObject {
    @Published private(set) var readIDs: Set<String>
    @Published private(set) var favoriteIDs: Set<String>
    @Published private(set) var paragraphPositions: [String: Int]

    private let defaults: UserDefaults
    private let readKey = "rss.article.readIDs"
    private let favoriteKey = "rss.article.favoriteIDs"
    private let positionKey = "rss.article.paragraphPositions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.readIDs = Set(defaults.stringArray(forKey: readKey) ?? [])
        self.favoriteIDs = Set(defaults.stringArray(forKey: favoriteKey) ?? [])
        self.paragraphPositions = (defaults.dictionary(forKey: positionKey) as? [String: NSNumber])?.reduce(into: [String: Int]()) { result, item in
            result[item.key] = max(0, item.value.intValue)
        } ?? [:]
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

    func paragraphPosition(for article: RSSArticlePreview) -> Int? { paragraphPositions[article.id] }

    func updateParagraphPosition(_ position: Int, for article: RSSArticlePreview) {
        let normalized = max(0, position)
        guard paragraphPositions[article.id] != normalized else { return }
        paragraphPositions[article.id] = normalized
        persist()
    }

    func clear(sourceURL: String? = nil) {
        if let sourceURL {
            let prefix = sourceURL + "|"
            readIDs = readIDs.filter { !$0.hasPrefix(prefix) }
            favoriteIDs = favoriteIDs.filter { !$0.hasPrefix(prefix) }
            paragraphPositions = paragraphPositions.filter { !$0.key.hasPrefix(prefix) }
        } else {
            readIDs.removeAll()
            favoriteIDs.removeAll()
            paragraphPositions.removeAll()
        }
        persist()
    }

    func backupSnapshot() -> RSSArticleStateSnapshot {
        RSSArticleStateSnapshot(readIDs: Array(readIDs), favoriteIDs: Array(favoriteIDs), paragraphPositions: paragraphPositions)
    }

    func restore(_ snapshot: RSSArticleStateSnapshot) {
        readIDs = Set(snapshot.readIDs)
        favoriteIDs = Set(snapshot.favoriteIDs)
        paragraphPositions = snapshot.paragraphPositions
        persist()
    }

    private func persist() {
        defaults.set(Array(readIDs), forKey: readKey)
        defaults.set(Array(favoriteIDs), forKey: favoriteKey)
        defaults.set(paragraphPositions, forKey: positionKey)
    }
}

struct RSSArticleStateSnapshot: Codable, Hashable, Sendable {
    let readIDs: [String]
    let favoriteIDs: [String]
    let paragraphPositions: [String: Int]

    init(readIDs: [String], favoriteIDs: [String], paragraphPositions: [String: Int] = [:]) {
        self.readIDs = readIDs
        self.favoriteIDs = favoriteIDs
        self.paragraphPositions = paragraphPositions
    }

    private enum CodingKeys: String, CodingKey { case readIDs, favoriteIDs, paragraphPositions }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readIDs = try container.decode([String].self, forKey: .readIDs)
        favoriteIDs = try container.decode([String].self, forKey: .favoriteIDs)
        paragraphPositions = try container.decodeIfPresent([String: Int].self, forKey: .paragraphPositions) ?? [:]
    }
}
