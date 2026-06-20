import Foundation
import SwiftSoup

struct SearchResultParser {
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
            let elements = try document.select(cleanCSS(listRule))
            var books: [SearchBook] = []
            for element in elements.array() {
                let name = try value(from: element, rule: firstRule(rule, keys: ["name", "bookName"]), fallback: "a@text")
                let bookUrl = try value(from: element, rule: firstRule(rule, keys: ["bookUrl", "url"]), fallback: "a@href")
                guard !name.isEmpty, !bookUrl.isEmpty else { continue }
                let author = try value(from: element, rule: firstRule(rule, keys: ["author"]), fallback: nil).nilIfEmpty
                let cover = try value(from: element, rule: firstRule(rule, keys: ["coverUrl", "cover"]), fallback: "img@src").nilIfEmpty
                books.append(SearchBook(
                    name: name,
                    author: author,
                    coverUrl: cover,
                    bookUrl: absolutize(bookUrl, base: response.url),
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
        let candidates = collectDictionaries(object).prefix(80)
        let books = candidates.compactMap { item -> SearchBook? in
            let name = pick(item, ["name", "bookName", "title", "book_name"])
            let url = pick(item, ["bookUrl", "url", "link", "book_url", "id"])
            guard let name, let url else { return nil }
            return SearchBook(
                name: name,
                author: pick(item, ["author", "writer"]),
                coverUrl: pick(item, ["cover", "coverUrl", "img", "image"]),
                bookUrl: absolutize(url, base: response.url),
                sourceName: source.bookSourceName,
                sourceUrl: source.bookSourceUrl,
                intro: pick(item, ["intro", "desc", "description"])
            )
        }
        return books.isEmpty ? .failure(.empty("JSON 搜索解析结果为空")) : .success(Array(books))
    }

    private func firstRule(_ rule: SourceRule, keys: [String]) -> String? {
        for key in keys {
            if let value = rule.fields[key], !value.isEmpty {
                return value
            }
        }
        return rule.raw
    }

    private func value(from element: Element, rule: String?, fallback: String?) throws -> String {
        let selectedRule = rule ?? fallback
        guard let selectedRule, !selectedRule.isEmpty else { return "" }
        let parts = selectedRule.components(separatedBy: "@")
        let selector = cleanCSS(parts.first ?? "")
        let target = selector.isEmpty ? element : try element.select(selector).first() ?? element
        let attr = parts.dropFirst().first ?? "text"
        if attr == "text" {
            return try target.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if attr == "html" {
            return try target.html().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try target.attr(attr).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanCSS(_ rule: String) -> String {
        rule
            .replacingOccurrences(of: "&&", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collectDictionaries(_ object: Any) -> [[String: Any]] {
        if let dict = object as? [String: Any] {
            var result = [dict]
            for value in dict.values {
                result.append(contentsOf: collectDictionaries(value))
            }
            return result
        }
        if let array = object as? [Any] {
            return array.flatMap { collectDictionaries($0) }
        }
        return []
    }

    private func pick(_ item: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = item[key] {
                let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, text != "<null>" {
                    return text
                }
            }
        }
        return nil
    }

    private func absolutize(_ text: String, base: URL) -> String {
        if let url = URL(string: text), url.scheme != nil {
            return url.absoluteString
        }
        return URL(string: text, relativeTo: base)?.absoluteURL.absoluteString ?? text
    }
}

