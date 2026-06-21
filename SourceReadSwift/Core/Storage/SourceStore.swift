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

    func importJSONData(_ data: Data) throws {
        let data = stripUTF8BOM(data)
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BookSource].self, from: data) {
            try importSources(list)
            return
        }
        if let wrapped = try? decoder.decode(WrappedBookSources.self, from: data),
           let list = wrapped.sources, !list.isEmpty {
            try importSources(list)
            return
        }
        let source = try decoder.decode(BookSource.self, from: data)
        try importSources([source])
    }

    func importSources(_ imported: [BookSource]) throws {
        let valid = imported.filter { !$0.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
                bookSourceName: "示例 HTML 源",
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
        do {
            try persistence.save(sources)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func remove(sourceURLs: Set<String>) {
        sources.removeAll { sourceURLs.contains($0.bookSourceUrl) }
        do {
            try persistence.save(sources)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, for sourceURLs: Set<String>) {
        sources = sources.map { source in
            sourceURLs.contains(source.bookSourceUrl) ? source.updatingEnabled(enabled) : source
        }
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
}

private struct WrappedBookSources: Decodable {
    let sources: [BookSource]?

    enum CodingKeys: String, CodingKey {
        case sources
        case bookSources
        case bookSource
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = (try? container.decode([BookSource].self, forKey: .sources))
            ?? (try? container.decode([BookSource].self, forKey: .bookSources))
            ?? (try? container.decode([BookSource].self, forKey: .bookSource))
            ?? (try? container.decode([BookSource].self, forKey: .data))
    }
}

enum SourceImportError: LocalizedError {
    case empty

    var errorDescription: String? {
        "没有找到有效书源"
    }
}
