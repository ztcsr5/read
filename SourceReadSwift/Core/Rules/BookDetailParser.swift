import Foundation
import SwiftSoup

struct BookDetailParser {
    private let extractor = HtmlRuleExtractor()

    func parse(source: BookSource, book: SearchBook, response: SourceResponse) -> Result<BookDetail, SourceEngineError> {
        do {
            let document = try SwiftSoup.parse(response.body, response.url.absoluteString)
            let rule = source.ruleBookInfo
            let name = try extractor.value(
                from: document,
                rule: extractor.firstRule(rule, keys: ["name", "bookName"]),
                fallback: nil,
                baseUrl: response.url
            ).nilIfEmpty ?? book.name
            let author = try extractor.value(
                from: document,
                rule: extractor.firstRule(rule, keys: ["author"]),
                fallback: nil,
                baseUrl: response.url
            ).nilIfEmpty ?? book.author
            let cover = try extractor.value(
                from: document,
                rule: extractor.firstRule(rule, keys: ["coverUrl", "cover"]),
                fallback: nil,
                baseUrl: response.url
            ).nilIfEmpty ?? book.coverUrl
            let intro = try extractor.value(
                from: document,
                rule: extractor.firstRule(rule, keys: ["intro", "introduction"]),
                fallback: nil,
                baseUrl: response.url
            ).nilIfEmpty ?? book.intro
            let latest = try extractor.value(
                from: document,
                rule: extractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
                fallback: nil,
                baseUrl: response.url
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
}

