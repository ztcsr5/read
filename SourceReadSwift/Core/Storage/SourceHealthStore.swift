import Foundation

enum SourceHealthStatus: String, Codable, Sendable {
    case passed
    case warning
    case failed
}

struct SourceHealthRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String { sourceURL }
    var sourceURL: String
    var sourceName: String
    var status: SourceHealthStatus
    var message: String
    var keyword: String
    var resultCount: Int
    var testedAt: Date
}

@MainActor
final class SourceHealthStore: ObservableObject {
    @Published private(set) var records: [String: SourceHealthRecord] = [:]
    @Published private(set) var lastError: String?

    private let persistence: SourceHealthPersistence

    init(persistence: SourceHealthPersistence = SourceHealthPersistence()) {
        self.persistence = persistence
        do {
            records = try persistence.load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func record(
        source: BookSource,
        status: SourceHealthStatus,
        message: String,
        keyword: String,
        resultCount: Int
    ) {
        records[source.bookSourceUrl] = SourceHealthRecord(
            sourceURL: source.bookSourceUrl,
            sourceName: source.bookSourceName,
            status: status,
            message: message,
            keyword: keyword,
            resultCount: resultCount,
            testedAt: Date()
        )
        persist()
    }

    func record(for source: BookSource) -> SourceHealthRecord? {
        records[source.bookSourceUrl]
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

struct SourceHealthPersistence {
    private let fileManager: FileManager
    private let fileName = "source_health.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [String: SourceHealthRecord] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: SourceHealthRecord].self, from: data)
    }

    func save(_ records: [String: SourceHealthRecord]) throws {
        let url = try storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(records)
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
