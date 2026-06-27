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
            let root: Element
            if let initRule = htmlExtractor.firstRule(rule, keys: ["init"]),
               let initialized = try htmlExtractor.select(from: document, rule: initRule, baseUrl: response.url).first {
                root = initialized
            } else {
                root = document
            }
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
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["name", "bookName"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.name
            let author = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["author"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.author
            let cover = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["coverUrl", "cover"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.coverUrl
            let intro = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["intro", "introduction"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.intro
            let latest = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty
            let tocUrl = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty

            return .success(BookDetail(
                name: name,
                author: author,
                coverUrl: cover,
                bookUrl: book.bookUrl,
                tocUrl: tocUrl,
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
        let rootObject: Any
        if let initRule = htmlExtractor.firstRule(source.ruleBookInfo, keys: ["init"]),
           let initialized = jsonExtractor.value(from: object, path: initRule, variables: ["source": source]) {
            rootObject = initialized
        } else {
            rootObject = object
        }

        let dict: [String: Any]
        if let direct = rootObject as? [String: Any] {
            dict = direct
        } else if let first = jsonExtractor.list(from: rootObject, rule: nil).first {
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
        )?.nilIfEmpty ?? book.name
        let author = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["author"]),
            fallbackKeys: ["author", "writer"],
            variables: variables
        )?.nilIfEmpty ?? book.author
        let cover = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["coverUrl", "cover"]),
            fallbackKeys: ["cover", "coverUrl", "img", "image"],
            variables: variables
        )?.nilIfEmpty ?? book.coverUrl
        let intro = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["intro", "introduction"]),
            fallbackKeys: ["intro", "desc", "description"],
            variables: variables
        )?.nilIfEmpty ?? book.intro
        let latest = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
            fallbackKeys: ["latestChapter", "lastChapter", "last"],
            variables: variables
        )?.nilIfEmpty
        let rawTocUrl = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl"]),
            fallbackKeys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl", "toc_url", "chapter_url"],
            variables: variables
        )?.nilIfEmpty
        let tocUrl = rawTocUrl.flatMap { resolveURL($0, base: response.url) }

        return .success(BookDetail(
            name: name,
            author: author,
            coverUrl: cover,
            bookUrl: book.bookUrl,
            tocUrl: tocUrl,
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: intro,
            latestChapter: latest
        ))
    }

    private func resolveURL(_ text: String, base: URL) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute.absoluteString
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL.absoluteString
    }
}
