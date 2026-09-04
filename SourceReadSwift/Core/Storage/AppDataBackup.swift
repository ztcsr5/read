import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// One portable, versioned document for moving the reader between devices.
/// Cookies/login sessions are deliberately excluded; they cannot be safely
/// exported and are re-established through the source login flow.
struct AppDataBackupSnapshot: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let bookshelf: BookshelfBackupSnapshot
    let sources: SourceLibrarySnapshot
    let purifyRules: [PurifyRule]
    let rssState: RSSArticleStateSnapshot
    let readerPreferences: [String: BackupPreferenceValue]

    init(
        schemaVersion: Int = 3,
        exportedAt: Date = Date(),
        bookshelf: BookshelfBackupSnapshot,
        sources: SourceLibrarySnapshot,
        purifyRules: [PurifyRule],
        rssState: RSSArticleStateSnapshot,
        readerPreferences: [String: BackupPreferenceValue]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.bookshelf = bookshelf
        self.sources = sources
        self.purifyRules = purifyRules
        self.rssState = rssState
        self.readerPreferences = readerPreferences
    }
}

/// Codable representation that keeps UserDefaults value types intact across devices.
/// The decoder also accepts the legacy plain-string representation emitted by schema v2.
enum BackupPreferenceValue: Codable, Hashable, Sendable {
    case string(String)
    case double(Double)
    case integer(Int)
    case bool(Bool)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum ValueType: String, Codable { case string, double, integer, bool }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let legacy = try? single.decode(String.self) {
            self = .string(legacy)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ValueType.self, forKey: .type) {
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        case .double: self = .double(try container.decode(Double.self, forKey: .value))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .value))
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

struct AppDataBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var snapshot: AppDataBackupSnapshot

    init(snapshot: AppDataBackupSnapshot) { self.snapshot = snapshot }

    init(configuration: ReadConfiguration) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshot = try decoder.decode(AppDataBackupSnapshot.self, from: configuration.file.regularFileContents ?? Data())
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
    }
}

enum AppDataBackupError: LocalizedError, Equatable {
    case emptyFile
    case fileReadFailed(String)
    case invalidJSON
    case unsupportedSchema(Int)
    case unsupportedBookshelfSchema(Int)
    case bookshelfRestoreFailed
    case sourceRestoreFailed
    case purifyRulesRestoreFailed

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "备份文件为空"
        case .fileReadFailed(let message): return "读取备份文件失败：\(message)"
        case .invalidJSON: return "备份不是有效的 SourceReadSwift JSON"
        case .unsupportedSchema(let value): return "备份版本 \(value) 不受支持"
        case .unsupportedBookshelfSchema(let value): return "书架备份版本 \(value) 不受支持"
        case .bookshelfRestoreFailed: return "书架数据恢复失败"
        case .sourceRestoreFailed: return "书源数据恢复失败"
        case .purifyRulesRestoreFailed: return "净化规则恢复失败"
        }
    }
}

/// One parser for full and legacy backup envelopes. Decoding and validation
/// finish before any store is mutated, preventing malformed files from causing
/// a partial restore.
enum AppDataBackupCodec {
    static let supportedSchemas = 1...3

    static func decode(
        data: Data,
        fallbackSources: SourceLibrarySnapshot,
        fallbackPurifyRules: [PurifyRule],
        fallbackRSSState: RSSArticleStateSnapshot
    ) throws -> AppDataBackupSnapshot {
        guard !data.isEmpty,
              data.contains(where: { !$0.isASCIIWhitespace }) else {
            throw AppDataBackupError.emptyFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot: AppDataBackupSnapshot
        if let full = try? decoder.decode(AppDataBackupSnapshot.self, from: data) {
            snapshot = full
        } else if let legacy = try? decoder.decode(BookshelfBackupSnapshot.self, from: data) {
            snapshot = AppDataBackupSnapshot(
                schemaVersion: 1,
                exportedAt: legacy.exportedAt,
                bookshelf: legacy,
                sources: fallbackSources,
                purifyRules: fallbackPurifyRules,
                rssState: fallbackRSSState,
                readerPreferences: [:]
            )
        } else {
            throw AppDataBackupError.invalidJSON
        }

        guard supportedSchemas.contains(snapshot.schemaVersion) else {
            throw AppDataBackupError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard snapshot.bookshelf.schemaVersion == 1 else {
            throw AppDataBackupError.unsupportedBookshelfSchema(snapshot.bookshelf.schemaVersion)
        }
        return snapshot
    }
}

/// Coordinates a full restore and rolls every store back to the pre-restore
/// snapshot when a later write fails. The store closures keep this workflow
/// unit-testable without constructing a SwiftUI Settings screen.
@MainActor
enum AppDataBackupRestorer {
    static func restore(
        _ snapshot: AppDataBackupSnapshot,
        previous: AppDataBackupSnapshot,
        restoreBookshelf: (BookshelfBackupSnapshot) -> Bool,
        restoreSources: (SourceLibrarySnapshot) -> Bool,
        restorePurifyRules: ([PurifyRule]) -> Bool,
        restoreRSSState: (RSSArticleStateSnapshot) -> Void,
        restorePreferences: ([String: BackupPreferenceValue]) -> Void
    ) throws {
        do {
            guard restoreBookshelf(snapshot.bookshelf) else {
                throw AppDataBackupError.bookshelfRestoreFailed
            }
            guard restoreSources(snapshot.sources) else {
                throw AppDataBackupError.sourceRestoreFailed
            }
            guard restorePurifyRules(snapshot.purifyRules) else {
                throw AppDataBackupError.purifyRulesRestoreFailed
            }
            restoreRSSState(snapshot.rssState)
            restorePreferences(snapshot.readerPreferences)
        } catch {
            // Rollback itself is best-effort: preserve the original stage
            // error so the UI can tell the user exactly where the import broke.
            _ = restoreBookshelf(previous.bookshelf)
            _ = restoreSources(previous.sources)
            _ = restorePurifyRules(previous.purifyRules)
            restoreRSSState(previous.rssState)
            restorePreferences(previous.readerPreferences)
            throw error
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}
