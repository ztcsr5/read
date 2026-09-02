import Foundation
import Combine

/// A resumable whole-book download record.  Only chapter indexes and
/// diagnostics are persisted; network credentials remain in SourceCookieStore.
struct ChapterDownloadRecord: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable {
        case queued
        case running
        case paused
        case completed
        case failed
        case cancelled
    }

    let id: String
    var sourceURL: String
    var bookURL: String
    var title: String
    var chapterCount: Int
    var completedIndexes: [Int]
    var failedIndexes: [Int]
    var status: Status
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    var completedCount: Int { completedIndexes.count }
    var failedCount: Int { failedIndexes.count }
    var progress: Double {
        guard chapterCount > 0 else { return 0 }
        return min(max(Double(completedCount) / Double(chapterCount), 0), 1)
    }

    init(
        id: String,
        sourceURL: String,
        bookURL: String,
        title: String,
        chapterCount: Int,
        completedIndexes: [Int] = [],
        failedIndexes: [Int] = [],
        status: Status = .queued,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.bookURL = bookURL
        self.title = title
        self.chapterCount = max(0, chapterCount)
        self.completedIndexes = Array(Set(completedIndexes.filter { $0 >= 0 })).sorted()
        self.failedIndexes = Array(Set(failedIndexes.filter { $0 >= 0 })).sorted()
        self.status = status
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ChapterDownloadPersistence {
    private let fileManager: FileManager
    private let fileName = "chapter_downloads.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [String: ChapterDownloadRecord] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records = try decoder.decode([String: ChapterDownloadRecord].self, from: Data(contentsOf: url))
        // A process can be killed while a task is running.  Treat that as a
        // resumable pause instead of leaving a permanently spinning record.
        for key in records.keys where records[key]?.status == .running {
            records[key]?.status = .paused
            records[key]?.updatedAt = Date()
        }
        return records
    }

    func save(_ records: [String: ChapterDownloadRecord]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL { return rootURL.appendingPathComponent(fileName) }
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true).appendingPathComponent(fileName)
    }
}

@MainActor
final class ChapterDownloadStore: ObservableObject {
    @Published private(set) var records: [String: ChapterDownloadRecord] = [:]
    @Published private(set) var lastError: String?

    private let persistence: ChapterDownloadPersistence

    init(persistence: ChapterDownloadPersistence = ChapterDownloadPersistence()) {
        self.persistence = persistence
        do {
            records = try persistence.load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func record(bookID: String) -> ChapterDownloadRecord? { records[bookID] }

    func begin(
        bookID: String,
        sourceURL: String,
        bookURL: String,
        title: String,
        chapterCount: Int
    ) {
        let old = records[bookID]
        let canResume = old?.sourceURL == sourceURL && old?.bookURL == bookURL && old?.chapterCount == chapterCount
        records[bookID] = ChapterDownloadRecord(
            id: bookID,
            sourceURL: sourceURL,
            bookURL: bookURL,
            title: title,
            chapterCount: chapterCount,
            completedIndexes: canResume ? (old?.completedIndexes ?? []) : [],
            failedIndexes: [],
            status: .queued,
            lastError: nil,
            createdAt: old?.createdAt ?? Date(),
            updatedAt: Date()
        )
        persist()
    }

    func markRunning(bookID: String) { update(bookID) { $0.status = .running; $0.lastError = nil } }
    func markPaused(bookID: String) { update(bookID) { $0.status = .paused } }
    func markCancelled(bookID: String) { update(bookID) { $0.status = .cancelled } }

    func markCompleted(bookID: String, chapterIndex: Int) {
        update(bookID) {
            $0.completedIndexes = Array(Set($0.completedIndexes + [chapterIndex])).sorted()
            $0.failedIndexes.removeAll { $0 == chapterIndex }
            $0.lastError = nil
        }
    }

    func markFailed(bookID: String, chapterIndex: Int, message: String) {
        update(bookID) {
            $0.failedIndexes = Array(Set($0.failedIndexes + [chapterIndex])).sorted()
            $0.lastError = message
            $0.status = .failed
        }
    }

    func finish(bookID: String) {
        update(bookID) {
            $0.status = $0.failedIndexes.isEmpty ? .completed : .failed
        }
    }

    func remove(bookID: String) {
        records.removeValue(forKey: bookID)
        persist()
    }

    private func update(_ bookID: String, _ mutation: (inout ChapterDownloadRecord) -> Void) {
        guard var record = records[bookID] else { return }
        mutation(&record)
        record.updatedAt = Date()
        records[bookID] = record
        persist()
    }

    private func persist() {
        do {
            try persistence.save(records)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Owns long-running cache jobs outside a view lifetime.  This prevents a
/// detail sheet disappearing from silently losing a whole-book download and
/// lets the next launch resume from the persisted chapter indexes.
@MainActor
final class ChapterDownloadCoordinator: ObservableObject {
    private let store: ChapterDownloadStore
    private var tasks: [String: Task<Void, Never>] = [:]

    init(store: ChapterDownloadStore) { self.store = store }

    func isRunning(bookID: String) -> Bool { tasks[bookID] != nil }

    func start(
        bookID: String,
        source: BookSource,
        title: String,
        chapters: [BookChapter],
        engine: SourceEngine,
        cacheStore: ChapterContentCacheStore,
        purifyRules: [String]
    ) {
        guard !chapters.isEmpty, tasks[bookID] == nil else { return }
        store.begin(
            bookID: bookID,
            sourceURL: source.bookSourceUrl,
            bookURL: chapters[0].bookUrl,
            title: title,
            chapterCount: chapters.count
        )
        store.markRunning(bookID: bookID)
        let task = Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            let current = store.record(bookID: bookID)
            let completed = Set(current?.completedIndexes ?? [])
            for chapter in chapters {
                guard !Task.isCancelled else {
                    store.markPaused(bookID: bookID)
                    self.tasks.removeValue(forKey: bookID)
                    return
                }
                guard !completed.contains(chapter.index) else { continue }
                let result = await AsyncTimeout.run(seconds: 14) {
                    await engine.getContent(source: source, chapter: chapter)
                } ?? .failure(.network("Download timed out"))
                guard !Task.isCancelled else {
                    store.markPaused(bookID: bookID)
                    self.tasks.removeValue(forKey: bookID)
                    return
                }
                switch result {
                case .success(let content):
                    cacheStore.save(content, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
                    store.markCompleted(bookID: bookID, chapterIndex: chapter.index)
                case .failure(let error):
                    store.markFailed(bookID: bookID, chapterIndex: chapter.index, message: error.displayMessage)
                }
            }
            store.finish(bookID: bookID)
            self.tasks.removeValue(forKey: bookID)
        }
        tasks[bookID] = task
    }

    func cancel(bookID: String) {
        tasks[bookID]?.cancel()
        tasks.removeValue(forKey: bookID)
        store.markCancelled(bookID: bookID)
    }
}
