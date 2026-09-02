import Foundation

enum SearchResultFilterScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case title
    case author
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .title: return "书名"
        case .author: return "作者"
        case .source: return "来源"
        }
    }

    var placeholder: String {
        switch self {
        case .all: return "筛选结果：书名、作者、来源、地址"
        case .title: return "筛选书名"
        case .author: return "筛选作者"
        case .source: return "筛选来源/分组/地址"
        }
    }
}

enum SearchResultFilter {
    static func apply(
        _ books: [SearchBook],
        query: String,
        scope: SearchResultFilterScope
    ) -> [SearchBook] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalized.isEmpty else { return books }
        return books.filter { book in
            switch scope {
            case .all:
                return [book.name, book.author ?? "", book.sourceName, book.sourceUrl, book.bookUrl]
                    .contains { contains($0, normalized) }
            case .title:
                return contains(book.name, normalized)
            case .author:
                return contains(book.author ?? "", normalized)
            case .source:
                return [book.sourceName, book.sourceUrl, book.bookUrl]
                    .contains { contains($0, normalized) }
            }
        }
    }

    private static func contains(_ value: String, _ query: String) -> Bool {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .localizedCaseInsensitiveContains(query)
    }
}
