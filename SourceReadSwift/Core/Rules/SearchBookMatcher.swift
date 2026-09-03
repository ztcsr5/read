import Foundation

enum SearchBookMatcher {
    static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

    static func filteredAndRanked(
        _ books: [SearchBook],
        keyword: String,
        exact: Bool
    ) -> [SearchBook] {
        let query = normalized(keyword)
        guard !query.isEmpty else { return [] }

        var seenIDs = Set<String>()
        let unique = books.filter { book in
            !normalized(book.name).isEmpty && seenIDs.insert(book.id).inserted
        }

        let matched = unique.filter { book in
            let name = normalized(book.name)
            let author = normalized(book.author ?? "")
            if exact { return name == query || author == query }
            return name.contains(query) || author.contains(query)
        }

        return matched.sorted { lhs, rhs in
            let left = score(lhs, query: query)
            let right = score(rhs, query: query)
            if left != right { return left > right }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.sourceName.localizedStandardCompare(rhs.sourceName) == .orderedAscending
        }
    }

    private static func score(_ book: SearchBook, query: String) -> Int {
        let name = normalized(book.name)
        let author = normalized(book.author ?? "")
        if name == query { return 400 }
        if name.hasPrefix(query) { return 300 }
        if name.contains(query) { return 200 }
        if author == query { return 150 }
        if author.contains(query) { return 100 }
        return 0
    }
}
