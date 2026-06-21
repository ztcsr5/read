import Foundation

struct ChapterContentCacheEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let sourceURL: String
    let chapterURL: String
    let bookURL: String
    let title: String
    let paragraphs: [String]
    let nextContentUrl: String?
    let purifySignature: String
    let cachedAt: Date

    var estimatedByteCount: Int {
        title.utf8.count
            + chapterURL.utf8.count
            + bookURL.utf8.count
            + paragraphs.reduce(0) { $0 + $1.utf8.count }
    }
}

@MainActor
final class ChapterContentCacheStore: ObservableObject {
    @Published private(set) var entries: [ChapterContentCacheEntry] = []
    @Published private(set) var lastError: String?

    private let persistence: ChapterContentCachePersistence
    private let maxEntryCount: Int

    var estimatedByteCount: Int {
        entries.reduce(0) { $0 + $1.estimatedByteCount }
    }

    init(
        persistence: ChapterContentCachePersistence = ChapterContentCachePersistence(),
        maxEntryCount: Int = 500
    ) {
        self.persistence = persistence
        self.maxEntryCount = maxEntryCount
        do {
            entries = Array(try persistence.load().prefix(maxEntryCount))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func content(sourceURL: String, chapter: BookChapter, purifyRules: [String]) -> ChapterContent? {
        let key = cacheKey(sourceURL: sourceURL, chapterURL: chapter.url)
        let signature = purifySignature(purifyRules)
        guard let entry = entries.first(where: { $0.key == key && $0.purifySignature == signature }) else {
            return nil
        }
        return ChapterContent(
            chapter: chapter,
            title: entry.title,
            paragraphs: entry.paragraphs,
            nextContentUrl: entry.nextContentUrl
        )
    }

    func isCached(sourceURL: String, chapter: BookChapter, purifyRules: [String]) -> Bool {
        content(sourceURL: sourceURL, chapter: chapter, purifyRules: purifyRules) != nil
    }

    func save(_ content: ChapterContent, sourceURL: String, purifyRules: [String]) {
        let entry = ChapterContentCacheEntry(
            key: cacheKey(sourceURL: sourceURL, chapterURL: content.chapter.url),
            sourceURL: sourceURL,
            chapterURL: content.chapter.url,
            bookURL: content.chapter.bookUrl,
            title: content.title,
            paragraphs: content.paragraphs,
            nextContentUrl: content.nextContentUrl,
            purifySignature: purifySignature(purifyRules),
            cachedAt: Date()
        )
        entries.removeAll { $0.key == entry.key }
        entries.insert(entry, at: 0)
        if entries.count > maxEntryCount {
            entries.removeLast(entries.count - maxEntryCount)
        }
        persist()
    }

    func removeExpired(olderThanDays days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        entries.removeAll { $0.cachedAt < cutoff }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    private func cacheKey(sourceURL: String, chapterURL: String) -> String {
        "\(sourceURL)|\(chapterURL)"
    }

    private func purifySignature(_ rules: [String]) -> String {
        rules.joined(separator: "\n")
    }

    private func persist() {
        do {
            try persistence.save(entries)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

struct ChapterContentCachePersistence {
    private let fileManager: FileManager
    private let fileName = "chapter_content_cache.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [ChapterContentCacheEntry] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ChapterContentCacheEntry].self, from: data)
    }

    func save(_ entries: [ChapterContentCacheEntry]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent(fileName)
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
