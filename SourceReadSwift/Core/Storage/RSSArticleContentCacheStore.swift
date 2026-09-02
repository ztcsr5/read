import Combine
import Foundation

struct RSSArticleContentCacheEntry: Codable, Hashable, Sendable {
    let articleID: String
    let paragraphs: [String]
    let contentHTML: String?
    let cachedAt: Date

    init(articleID: String, paragraphs: [String], contentHTML: String? = nil, cachedAt: Date) {
        self.articleID = articleID
        self.paragraphs = paragraphs
        self.contentHTML = contentHTML
        self.cachedAt = cachedAt
    }

    private enum CodingKeys: String, CodingKey { case articleID, paragraphs, contentHTML, cachedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        articleID = try c.decode(String.self, forKey: .articleID)
        paragraphs = try c.decode([String].self, forKey: .paragraphs)
        contentHTML = try c.decodeIfPresent(String.self, forKey: .contentHTML)
        cachedAt = try c.decode(Date.self, forKey: .cachedAt)
    }
}

@MainActor
final class RSSArticleContentCacheStore: ObservableObject {
    @Published private(set) var entries: [RSSArticleContentCacheEntry] = []

    private let fileURL: URL
    private let maxEntries: Int

    init(fileURL: URL? = nil, maxEntries: Int = 200) {
        self.maxEntries = maxEntries
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("SourceReadSwift/RSSArticleContentCache.json")
        }

        guard let data = try? Data(contentsOf: self.fileURL),
              let decoded = try? Self.decoder.decode([RSSArticleContentCacheEntry].self, from: data) else { return }
        entries = decoded
    }

    func paragraphs(for article: RSSArticlePreview, maxAge: TimeInterval? = nil) -> [String]? {
        guard let entry = entries.first(where: { $0.articleID == article.id }) else { return nil }
        if let maxAge, Date().timeIntervalSince(entry.cachedAt) > maxAge { return nil }
        return entry.paragraphs
    }

    func contentHTML(for article: RSSArticlePreview, maxAge: TimeInterval? = nil) -> String? {
        guard let entry = entries.first(where: { $0.articleID == article.id }) else { return nil }
        if let maxAge, Date().timeIntervalSince(entry.cachedAt) > maxAge { return nil }
        return entry.contentHTML
    }

    func cachedAt(for article: RSSArticlePreview) -> Date? {
        entries.first(where: { $0.articleID == article.id })?.cachedAt
    }

    func save(_ paragraphs: [String], for article: RSSArticlePreview, contentHTML: String? = nil) {
        let normalized = paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }
        let entry = RSSArticleContentCacheEntry(articleID: article.id, paragraphs: normalized, contentHTML: contentHTML, cachedAt: Date())
        entries.removeAll { $0.articleID == article.id }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        persist()
    }

    func remove(articleID: String) {
        entries.removeAll { $0.articleID == articleID }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(entries).write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort cache; article reading remains functional when disk writes fail.
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
