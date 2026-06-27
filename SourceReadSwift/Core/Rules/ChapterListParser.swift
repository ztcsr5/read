import Foundation
import SwiftSoup

struct ChapterListParser {
    private let htmlExtractor = HtmlRuleExtractor()
    private let jsonExtractor = JSONRuleExtractor()

    func parse(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<[BookChapter], SourceEngineError> {
        switch parsePage(source: source, book: book, response: response) {
        case .success(let page):
            return page.chapters.isEmpty ? .failure(.empty("Chapter list is empty")) : .success(page.chapters)
        case .failure(let error):
            return .failure(error)
        }
    }

    func parsePage(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<ChapterListPage, SourceEngineError> {
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "{" || body.first == "[" {
            return parseJSON(source: source, book: book, response: response)
        }
        return parseHTML(source: source, book: book, response: response)
    }

    private func parseHTML(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<ChapterListPage, SourceEngineError> {
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
        guard let listRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"]) else {
            return .failure(.rule("ruleToc.chapterList is empty"))
        }

        do {
            let roots: [Element]
            if let initRule = htmlExtractor.firstRule(source.ruleToc, keys: ["init"]) {
                roots = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: initRule)
            } else {
                roots = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html")
            }
            let elements = try roots.flatMap { root in
                try htmlExtractor.select(from: root, rule: listRule, baseUrl: response.url)
            }
            let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
            let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])
            let nextRule = htmlExtractor.firstRule(source.ruleToc, keys: ["nextTocUrl", "nextChapterUrl", "nextUrl"])

            let chapters = try elements.enumerated().compactMap { index, element -> BookChapter? in
                let title = try htmlExtractor.value(from: element, rule: nameRule, fallback: "a@text", baseUrl: response.url, variables: variables)
                let url = try htmlExtractor.value(from: element, rule: urlRule, fallback: "a@href", baseUrl: response.url, variables: variables)
                guard !title.isEmpty, !url.isEmpty else { return nil }
                return BookChapter(title: title, url: url, bookUrl: book.bookUrl, index: index, isVip: false)
            }
            var next: String?
            for root in roots {
                next = try htmlExtractor.value(from: root, rule: nextRule, fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                if next != nil { break }
            }

            return chapters.isEmpty
                ? .failure(.empty("Chapter list is empty"))
                : .success(ChapterListPage(chapters: chapters, nextTocUrl: next))
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<ChapterListPage, SourceEngineError> {
        guard let data = response.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.rule("JSON parse failed"))
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
        let rootObject: Any
        if let initRule = htmlExtractor.firstRule(source.ruleToc, keys: ["init"]),
           let initialized = jsonExtractor.value(from: object, path: initRule, variables: variables) {
            rootObject = initialized
        } else {
            rootObject = object
        }
        let listRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"])
        let items = jsonExtractor.list(from: rootObject, rule: listRule, variables: variables)
        let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
        let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])
        let nextRule = htmlExtractor.firstRule(source.ruleToc, keys: ["nextTocUrl", "nextChapterUrl", "nextUrl"])

        let chapters = items.enumerated().compactMap { index, item -> BookChapter? in
            let title = jsonExtractor.string(
                from: item,
                rule: nameRule,
                fallbackKeys: ["chapterName", "name", "title", "chapterTitle"],
                variables: variables
            )
            let rawUrl = jsonExtractor.string(
                from: item,
                rule: urlRule,
                fallbackKeys: ["chapterUrl", "url", "link", "id", "cid"],
                variables: variables
            )
            guard let title, let rawUrl, !title.isEmpty, !rawUrl.isEmpty else { return nil }
            return BookChapter(
                title: title,
                url: htmlExtractor.absolutize(rawUrl, base: response.url),
                bookUrl: book.bookUrl,
                index: index,
                isVip: false
            )
        }

        let next: String?
        if let dict = rootObject as? [String: Any] {
            next = jsonExtractor.string(
                from: dict,
                rule: nextRule,
                fallbackKeys: ["nextTocUrl", "nextChapterUrl", "nextUrl", "next"],
                variables: variables
            ).map { htmlExtractor.absolutize($0, base: response.url) }
        } else {
            next = nil
        }

        return chapters.isEmpty
            ? .failure(.empty("JSON chapter list is empty"))
            : .success(ChapterListPage(chapters: chapters, nextTocUrl: next))
    }
}

struct ChapterListPage: Equatable, Sendable {
    let chapters: [BookChapter]
    let nextTocUrl: String?
}
