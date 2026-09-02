import Foundation
import Combine

struct RSSFeedCacheEntry: Codable, Hashable, Sendable {
    let sourceURL: String
    let articles: [RSSArticlePreview]
    let cachedAt: Date
}

@MainActor
final class RSSFeedCacheStore: ObservableObject {
    @Published private(set) var entries: [RSSFeedCacheEntry] = []
    private let fileURL: URL
    private let maxSources: Int

    init(fileURL: URL? = nil, maxSources: Int = 50) {
        self.maxSources = maxSources
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("SourceReadSwift/RSSFeedCache.json")
        }
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([RSSFeedCacheEntry].self, from: data) {
            entries = decoded
        }
    }

    func articles(for sourceURL: String, maxAge: TimeInterval? = nil) -> [RSSArticlePreview]? {
        guard let entry = entries.first(where: { $0.sourceURL == sourceURL }) else { return nil }
        if let maxAge, Date().timeIntervalSince(entry.cachedAt) > maxAge { return nil }
        return entry.articles
    }

    func save(_ articles: [RSSArticlePreview], sourceURL: String) {
        let entry = RSSFeedCacheEntry(sourceURL: sourceURL, articles: Array(articles.prefix(100)), cachedAt: Date())
        entries.removeAll { $0.sourceURL == sourceURL }
        entries.insert(entry, at: 0)
        if entries.count > maxSources { entries.removeLast(entries.count - maxSources) }
        persist()
    }

    func remove(sourceURL: String) {
        entries.removeAll { $0.sourceURL == sourceURL }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: fileURL, options: [.atomic])
        } catch {
            // Cache is best-effort; network reading remains functional when disk writes fail.
        }
    }
}
