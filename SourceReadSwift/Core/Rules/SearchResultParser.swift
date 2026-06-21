import Foundation
import SwiftSoup

struct SearchResultParser {
    private let htmlExtractor = HtmlRuleExtractor()

    func parse(source: BookSource, response: SourceResponse) -> Result<[SearchBook], SourceEngineError> {
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "{" || body.first == "[" {
            return parseJSON(source: source, response: response)
        }
        return parseHTML(source: source, response: response)
    }

    private func parseHTML(source: BookSource, response: SourceResponse) -> Result<[SearchBook], SourceEngineError> {
        guard let rule = source.ruleSearch else {
            return .failure(.rule("ruleSearch 为空"))
        }
        guard let listRule = firstRule(rule, keys: ["bookList", "list", "books"]) else {
            return .failure(.rule("ruleSearch.bookList 为空"))
        }

        do {
            let document = try SwiftSoup.parse(response.body, response.url.absoluteString)
            let elements = try document.select(htmlExtractor.cleanCSS(listRule))
            var books: [SearchBook] = []
            for element in elements.array() {
                let name = try htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["name", "bookName"]), fallback: "a@text", baseUrl: response.url)
                let bookUrl = try htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["bookUrl", "url"]), fallback: "a@href", baseUrl: response.url)
                guard !name.isEmpty, !bookUrl.isEmpty else { continue }
                let author = try htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["author"]), fallback: nil, baseUrl: response.url).nilIfEmpty
                let cover = try htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["coverUrl", "cover"]), fallback: "img@src", baseUrl: response.url).nilIfEmpty
                books.append(SearchBook(
                    name: name,
                    author: author,
                    coverUrl: cover,
                    bookUrl: bookUrl,
                    sourceName: source.bookSourceName,
                    sourceUrl: source.bookSourceUrl,
                    intro: nil
                ))
            }
            return books.isEmpty ? .failure(.empty("搜索解析结果为空")) : .success(books)
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, response: SourceResponse) -> Result<[SearchBook], SourceEngineError> {
        guard let data = response.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.rule("JSON 解析失败"))
        }
        let extractor = JSONRuleExtractor()
        let rule = source.ruleSearch
        let listRule = firstRule(rule, keys: ["bookList", "list", "books"])
        let candidates = extractor.list(from: object, rule: listRule).prefix(120)
        let books = candidates.compactMap { item -> SearchBook? in
            let name = extractor.string(
                from: item,
                rule: firstRule(rule, keys: ["name", "bookName"]),
                fallbackKeys: ["name", "bookName", "title", "book_name"]
            )
            let url = extractor.string(
                from: item,
                rule: firstRule(rule, keys: ["bookUrl", "url"]),
                fallbackKeys: ["bookUrl", "url", "link", "book_url", "id"]
            )
            guard let name, let url else { return nil }
            return SearchBook(
                name: name,
                author: extractor.string(
                    from: item,
                    rule: firstRule(rule, keys: ["author"]),
                    fallbackKeys: ["author", "writer"]
                ),
                coverUrl: extractor.string(
                    from: item,
                    rule: firstRule(rule, keys: ["coverUrl", "cover"]),
                    fallbackKeys: ["cover", "coverUrl", "img", "image"]
                ),
                bookUrl: htmlExtractor.absolutize(url, base: response.url),
                sourceName: source.bookSourceName,
                sourceUrl: source.bookSourceUrl,
                intro: extractor.string(
                    from: item,
                    rule: firstRule(rule, keys: ["intro"]),
                    fallbackKeys: ["intro", "desc", "description"]
                )
            )
        }
        return books.isEmpty ? .failure(.empty("JSON 搜索解析结果为空")) : .success(Array(books))
    }

    private func firstRule(_ rule: SourceRule?, keys: [String]) -> String? {
        guard let rule else { return nil }
        for key in keys {
            if let value = rule.fields[key], !value.isEmpty {
                return value
            }
        }
        return rule.raw
    }

}
