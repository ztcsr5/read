import Foundation

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var sources: [BookSource] = []
    @Published private(set) var lastError: String?
    private let persistence: SourcePersistence

    init(persistence: SourcePersistence = SourcePersistence()) {
        self.persistence = persistence
        do {
            sources = try persistence.load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importJSON(_ text: String) throws {
        try importJSONData(Data(text.utf8))
    }

    @discardableResult
    func importSmartInput(_ input: String) throws -> SourceImportInput {
        let parsed = SourceImportLinkParser.parse(input)
        switch parsed.kind {
        case .empty:
            throw SourceImportError.empty
        case .json:
            try importJSON(parsed.value)
        case .url:
            throw SourceImportError.urlImportRequired(parsed.value)
        case .unsupportedScheme:
            throw SourceImportError.unsupportedScheme
        case .unknown:
            throw SourceImportError.unknownInput
        }
        return parsed
    }

    func importJSONData(_ data: Data) throws {
        let normalized = try normalizeImportData(stripUTF8BOM(data))
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BookSource].self, from: normalized) {
            try importSources(list)
            return
        }
        if let wrapped = try? decoder.decode(WrappedBookSources.self, from: normalized),
           let list = wrapped.sources, !list.isEmpty {
            try importSources(list)
            return
        }
        let source = try decoder.decode(BookSource.self, from: normalized)
        try importSources([source])
    }

    func importSources(_ imported: [BookSource]) throws {
        let valid = imported.filter {
            !$0.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else {
            throw SourceImportError.empty
        }
        sources = merge(existing: sources, incoming: valid)
        try persistence.save(sources)
        lastError = nil
    }

    func seedForDevelopment() {
        guard sources.isEmpty else { return }
        sources = [
            BookSource(
                bookSourceName: "Example HTML Source",
                bookSourceUrl: "https://example.com",
                searchUrl: "https://example.com/search?q={{keyword}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": ".book",
                    "name": ".title@text",
                    "author": ".author@text",
                    "bookUrl": "a@href",
                    "coverUrl": "img@src"
                ])
            )
        ]
    }

    func source(for sourceUrl: String) -> BookSource? {
        sources.first { $0.bookSourceUrl == sourceUrl }
    }

    func remove(_ source: BookSource) {
        sources.removeAll { $0.bookSourceUrl == source.bookSourceUrl }
        saveAfterMutation()
    }

    func remove(sourceURLs: Set<String>) {
        sources.removeAll { sourceURLs.contains($0.bookSourceUrl) }
        saveAfterMutation()
    }

    func setEnabled(_ enabled: Bool, for sourceURLs: Set<String>) {
        sources = sources.map { source in
            sourceURLs.contains(source.bookSourceUrl) ? source.updatingEnabled(enabled) : source
        }
        saveAfterMutation()
    }

    private func saveAfterMutation() {
        do {
            try persistence.save(sources)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func merge(existing: [BookSource], incoming: [BookSource]) -> [BookSource] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.bookSourceUrl, $0) })
        for item in incoming {
            map[item.bookSourceUrl] = item
        }
        return map.values.sorted { $0.bookSourceName < $1.bookSourceName }
    }

    private func stripUTF8BOM(_ data: Data) -> Data {
        let bom = Data([0xEF, 0xBB, 0xBF])
        guard data.starts(with: bom) else { return data }
        return data.dropFirst(3)
    }

    private func normalizeImportData(_ data: Data) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = try? JSONDecoder().decode(String.self, from: Data(text.utf8)) {
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return Data(text.utf8)
        }
        if let extracted = extractFirstJSONValue(from: text) {
            return Data(extracted.utf8)
        }
        return data
    }

    private func extractFirstJSONValue(from text: String) -> String? {
        let chars = Array(text)
        for start in chars.indices where chars[start] == "{" || chars[start] == "[" {
            let open = chars[start]
            let close: Character = open == "{" ? "}" : "]"
            var depth = 0
            var inString = false
            var escaped = false
            for index in start..<chars.count {
                let char = chars[index]
                if inString {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        inString = false
                    }
                    continue
                }
                if char == "\"" {
                    inString = true
                } else if char == open {
                    depth += 1
                } else if char == close {
                    depth -= 1
                    if depth == 0 {
                        return String(chars[start...index])
                    }
                }
            }
        }
        return nil
    }
}

private struct WrappedBookSources: Decodable {
    let sources: [BookSource]?

    enum CodingKeys: String, CodingKey {
        case sources
        case bookSources
        case bookSource
        case data
        case list
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = (try? container.decode([BookSource].self, forKey: .sources))
            ?? (try? container.decode([BookSource].self, forKey: .bookSources))
            ?? (try? container.decode([BookSource].self, forKey: .bookSource))
            ?? (try? container.decode([BookSource].self, forKey: .data))
            ?? (try? container.decode([BookSource].self, forKey: .list))
            ?? (try? container.decode([BookSource].self, forKey: .items))
    }
}

enum SourceImportError: LocalizedError {
    case empty
    case urlImportRequired(String)
    case unsupportedScheme
    case unknownInput

    var errorDescription: String? {
        switch self {
        case .empty:
            return "No valid book source was found."
        case .urlImportRequired(let url):
            return "URL import requires downloading first: \(url)"
        case .unsupportedScheme:
            return "Import link was recognized, but no src/url parameter was found."
        case .unknownInput:
            return "Input is not recognized as JSON, an HTTP URL, or a reader import link."
        }
    }
}
