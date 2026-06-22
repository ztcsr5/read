import Foundation
import SwiftSoup

struct BookDetailParser {
    private let htmlExtractor = HtmlRuleExtractor()
    private let jsonExtractor = JSONRuleExtractor()

    func parse(source: BookSource, book: SearchBook, response: SourceResponse) -> Result<BookDetail, SourceEngineError> {
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "{" || body.first == "[" {
            return parseJSON(source: source, book: book, response: response)
        }
        return parseHTML(source: source, book: book, response: response)
    }

    private func parseHTML(source: BookSource, book: SearchBook, response: SourceResponse) -> Result<BookDetail, SourceEngineError> {
        do {
            let document = try SwiftSoup.parse(response.body, response.url.absoluteString)
            let rule = source.ruleBookInfo
            let bookMap: [String: Any] = [
                "name": book.name,
                "author": book.author ?? "",
                "coverUrl": book.coverUrl ?? "",
                "bookUrl": book.bookUrl,
                "intro": book.intro ?? ""
            ]
            let variables: [String: Any] = [
                "source": source,
                "book": bookMap
            ]
            let name = try htmlExtractor.value(
                from: document,
                rule: htmlExtractor.firstRule(rule, keys: ["name", "bookName"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.name
            let author = try htmlExtractor.value(
                from: document,
                rule: htmlExtractor.firstRule(rule, keys: ["author"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.author
            let cover = try htmlExtractor.value(
                from: document,
                rule: htmlExtractor.firstRule(rule, keys: ["coverUrl", "cover"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.coverUrl
            let intro = try htmlExtractor.value(
                from: document,
                rule: htmlExtractor.firstRule(rule, keys: ["intro", "introduction"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.intro
            let latest = try htmlExtractor.value(
                from: document,
                rule: htmlExtractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty

            return .success(BookDetail(
                name: name,
                author: author,
                coverUrl: cover,
                bookUrl: book.bookUrl,
                sourceName: source.bookSourceName,
                sourceUrl: source.bookSourceUrl,
                intro: intro,
                latestChapter: latest
            ))
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, book: SearchBook, response: SourceResponse) -> Result<BookDetail, SourceEngineError> {
        guard let data = response.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.rule("JSON 解析失败"))
        }
        let dict: [String: Any]
        if let direct = object as? [String: Any] {
            dict = direct
        } else if let first = jsonExtractor.list(from: object, rule: nil).first {
            dict = first
        } else {
            return .failure(.empty("JSON 详情为空"))
        }

        let rule = source.ruleBookInfo
        let bookMap: [String: Any] = [
            "name": book.name,
            "author": book.author ?? "",
            "coverUrl": book.coverUrl ?? "",
            "bookUrl": book.bookUrl,
            "intro": book.intro ?? ""
        ]
        let variables: [String: Any] = [
            "source": source,
            "book": bookMap
        ]
        let name = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["name", "bookName"]),
            fallbackKeys: ["name", "bookName", "title", "book_name"],
            variables: variables
        ) ?? book.name
        let author = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["author"]),
            fallbackKeys: ["author", "writer"],
            variables: variables
        ) ?? book.author
        let cover = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["coverUrl", "cover"]),
            fallbackKeys: ["cover", "coverUrl", "img", "image"],
            variables: variables
        ) ?? book.coverUrl
        let intro = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["intro", "introduction"]),
            fallbackKeys: ["intro", "desc", "description"],
            variables: variables
        ) ?? book.intro
        let latest = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
            fallbackKeys: ["latestChapter", "lastChapter", "last"],
            variables: variables
        )

        return .success(BookDetail(
            name: name,
            author: author,
            coverUrl: cover,
            bookUrl: book.bookUrl,
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: intro,
            latestChapter: latest
        ))
    }
}
