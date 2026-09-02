import Foundation

struct SourceDiagnosticHistoryRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let sourceURL: String
    let sourceName: String
    let stage: String
    let status: SourceHealthStatus
    let message: String
    let elapsedMilliseconds: Int?
    let resultCount: Int
    let testedAt: Date

    init(
        id: UUID = UUID(),
        sourceURL: String,
        sourceName: String,
        stage: String,
        status: SourceHealthStatus,
        message: String,
        elapsedMilliseconds: Int? = nil,
        resultCount: Int = 0,
        testedAt: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.stage = stage
        self.status = status
        self.message = message
        self.elapsedMilliseconds = elapsedMilliseconds
        self.resultCount = resultCount
        self.testedAt = testedAt
    }
}

@MainActor
final class SourceDiagnosticHistoryStore: ObservableObject {
    static let defaultLimit = 80

    @Published private(set) var records: [String: [SourceDiagnosticHistoryRecord]] = [:]
    @Published private(set) var lastError: String?

    private let persistence: SourceDiagnosticHistoryPersistence
    private let limit: Int

    init(
        persistence: SourceDiagnosticHistoryPersistence = SourceDiagnosticHistoryPersistence(),
        limit: Int = SourceDiagnosticHistoryStore.defaultLimit
    ) {
        self.persistence = persistence
        self.limit = max(1, limit)
        do {
            records = try persistence.load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func record(
        source: BookSource,
        stage: String,
        status: SourceHealthStatus,
        message: String,
        elapsedMilliseconds: Int? = nil,
        resultCount: Int = 0
    ) {
        record(
            sourceURL: source.bookSourceUrl,
            sourceName: source.bookSourceName,
            stage: stage,
            status: status,
            message: message,
            elapsedMilliseconds: elapsedMilliseconds,
            resultCount: resultCount
        )
    }

    func record(
        sourceURL: String,
        sourceName: String,
        stage: String,
        status: SourceHealthStatus,
        message: String,
        elapsedMilliseconds: Int? = nil,
        resultCount: Int = 0
    ) {
        let entry = SourceDiagnosticHistoryRecord(
            sourceURL: sourceURL,
            sourceName: sourceName,
            stage: stage,
            status: status,
            message: message,
            elapsedMilliseconds: elapsedMilliseconds,
            resultCount: resultCount
        )
        records[sourceURL, default: []].insert(entry, at: 0)
        if records[sourceURL]!.count > limit {
            records[sourceURL] = Array(records[sourceURL]!.prefix(limit))
        }
        persist()
    }

    func records(for source: BookSource) -> [SourceDiagnosticHistoryRecord] {
        records[source.bookSourceUrl] ?? []
    }

    func clear(for source: BookSource) {
        records.removeValue(forKey: source.bookSourceUrl)
        persist()
    }

    func clearAll() {
        records.removeAll()
        persist()
    }

    func exportText(for source: BookSource) -> String {
        let entries = records(for: source)
        guard !entries.isEmpty else { return "暂无诊断历史" }
        var lines = ["Source diagnostic history", "source: \(source.bookSourceName)", "url: \(source.bookSourceUrl)"]
        for entry in entries {
            let elapsed = entry.elapsedMilliseconds.map { "\($0) ms" } ?? "-"
            lines.append("[\(entry.status.rawValue)] \(entry.stage) · \(entry.testedAt.formatted(date: .abbreviated, time: .shortened)) · \(elapsed) · results=\(entry.resultCount)")
            lines.append(entry.message)
        }
        return lines.joined(separator: "\n")
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

struct SourceDiagnosticHistoryPersistence {
    private let fileManager: FileManager
    private let fileName = "source_diagnostic_history.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [String: [SourceDiagnosticHistoryRecord]] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: [SourceDiagnosticHistoryRecord]].self, from: Data(contentsOf: url))
    }

    func save(_ records: [String: [SourceDiagnosticHistoryRecord]]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        if let rootURL { return rootURL.appendingPathComponent(fileName) }
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("SourceReadSwift", isDirectory: true).appendingPathComponent(fileName)
    }
}
