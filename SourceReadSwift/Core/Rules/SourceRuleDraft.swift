import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Codable, source-scoped editor state.  Keeping drafts separate from
/// `BookSource` means an unfinished edit can be restored without mutating the
/// active source or its persistent cookie/token state.
struct SourceRuleDraft: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceURL: String
    let sourceName: String
    var searchURL: String
    var searchRule: String
    var detailRule: String
    var tocRule: String
    var contentRule: String
    let updatedAt: Date

    static let currentSchemaVersion = 1

    init(
        sourceURL: String,
        sourceName: String,
        searchURL: String,
        searchRule: String,
        detailRule: String,
        tocRule: String,
        contentRule: String,
        updatedAt: Date = Date(),
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.searchURL = searchURL
        self.searchRule = searchRule
        self.detailRule = detailRule
        self.tocRule = tocRule
        self.contentRule = contentRule
        self.updatedAt = updatedAt
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SourceRuleDraft {
        guard !data.isEmpty,
              data.contains(where: { !$0.isASCIIWhitespace }) else {
            throw SourceRuleDraftError.emptyFile
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let draft = try decoder.decode(SourceRuleDraft.self, from: data)
        guard (1...currentSchemaVersion).contains(draft.schemaVersion) else {
            throw SourceRuleDraftError.unsupportedSchema(draft.schemaVersion)
        }
        return draft
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}

/// File-backed representation used by the rule editor's document importer and
/// exporter.  The payload intentionally stays the same as `SourceRuleDraft`
/// so files are portable between app versions and can also be inspected or
/// edited as ordinary JSON.
struct SourceRuleDraftDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var draft: SourceRuleDraft

    init(draft: SourceRuleDraft) {
        self.draft = draft
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, !data.isEmpty else {
            throw SourceRuleDraftError.emptyFile
        }
        draft = try SourceRuleDraft.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try draft.jsonData())
    }
}

enum SourceRuleDraftError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case sourceMismatch
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "规则草稿版本 \(version) 不受支持"
        case .sourceMismatch: return "草稿不属于当前书源"
        case .emptyFile: return "规则草稿文件为空"
        }
    }
}

final class SourceRuleDraftStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix = "SourceReadSwift.ruleDraft."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(sourceURL: String) -> SourceRuleDraft? {
        guard let data = defaults.data(forKey: key(for: sourceURL)) else { return nil }
        return try? SourceRuleDraft.decode(data)
    }

    func save(_ draft: SourceRuleDraft) throws {
        defaults.set(try draft.jsonData(), forKey: key(for: draft.sourceURL))
    }

    func remove(sourceURL: String) {
        defaults.removeObject(forKey: key(for: sourceURL))
    }

    private func key(for sourceURL: String) -> String {
        // Keep separators escaped as well.  A letters-and-digits-only key can
        // collapse distinct URLs (for example `/a-b` and `/ab`) into the same
        // UserDefaults slot, which would make drafts leak across sources.
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        let encoded = sourceURL.addingPercentEncoding(withAllowedCharacters: safeCharacters) ?? sourceURL
        return prefix + encoded
    }
}
