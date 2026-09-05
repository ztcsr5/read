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

        let unique = deduplicated(books)

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

    /// De-duplicates incrementally collected source results while retaining
    /// the first source's metadata.  Search requests arrive out of order, so
    /// the caller can run this after each batch without reshuffling equal
    /// scores unpredictably.
    static func deduplicated(_ books: [SearchBook]) -> [SearchBook] {
        var seenIDs = Set<String>()
        return books.filter { book in
            let name = normalized(book.name)
            guard !name.isEmpty else { return false }
            let normalizedURL = book.bookUrl
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            let source = book.sourceUrl
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            let id = "\(source)|\(normalizedURL)"
            // Some sources return the same item once as an absolute URL and
            // once as a path. Keep distinct source URLs, but collapse exact
            // duplicates from the same source regardless of slash casing.
            return seenIDs.insert(id).inserted
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
