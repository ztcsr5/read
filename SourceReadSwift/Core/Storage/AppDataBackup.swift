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
