import Foundation

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var sources: [BookSource] = []

    func importJSON(_ text: String) throws {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BookSource].self, from: data) {
            sources = merge(existing: sources, incoming: list)
            return
        }
        let source = try decoder.decode(BookSource.self, from: data)
        sources = merge(existing: sources, incoming: [source])
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

    private func merge(existing: [BookSource], incoming: [BookSource]) -> [BookSource] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.bookSourceUrl, $0) })
        for item in incoming {
            map[item.bookSourceUrl] = item
        }
        return map.values.sorted { $0.bookSourceName < $1.bookSourceName }
    }
}

