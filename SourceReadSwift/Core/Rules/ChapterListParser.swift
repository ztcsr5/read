import Foundation

struct ChapterListParser {
    private let htmlExtractor = HtmlRuleExtractor()
    private let jsonExtractor = JSONRuleExtractor()

    func parse(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<[BookChapter], SourceEngineError> {
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "{" || body.first == "[" {
            return parseJSON(source: source, book: book, response: response)
        }
        return parseHTML(source: source, book: book, response: response)
    }

    private func parseHTML(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<[BookChapter], SourceEngineError> {
        guard let listRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"]) else {
            return .failure(.rule("ruleToc.chapterList \u{4e3a}\u{7a7a}"))
        }

        do {
            let elements = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: listRule)
            let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
            let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])

            let chapters = try elements.enumerated().compactMap { index, element -> BookChapter? in
                let title = try htmlExtractor.value(from: element, rule: nameRule, fallback: "a@text", baseUrl: response.url)
                let url = try htmlExtractor.value(from: element, rule: urlRule, fallback: "a@href", baseUrl: response.url)
                guard !title.isEmpty, !url.isEmpty else { return nil }
                return BookChapter(title: title, url: url, bookUrl: book.bookUrl, index: index, isVip: false)
            }
            return chapters.isEmpty ? .failure(.empty("\u{76ee}\u{5f55}\u{89e3}\u{6790}\u{7ed3}\u{679c}\u{4e3a}\u{7a7a}")) : .success(chapters)
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<[BookChapter], SourceEngineError> {
        guard let data = response.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.rule("JSON \u{89e3}\u{6790}\u{5931}\u{8d25}"))
        }
        let listRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"])
        let items = jsonExtractor.list(from: object, rule: listRule)
        let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
        let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])

        let chapters = items.enumerated().compactMap { index, item -> BookChapter? in
            let title = jsonExtractor.string(
                from: item,
                rule: nameRule,
                fallbackKeys: ["chapterName", "name", "title", "chapterTitle"]
            )
            let rawUrl = jsonExtractor.string(
                from: item,
                rule: urlRule,
                fallbackKeys: ["chapterUrl", "url", "link", "id", "cid"]
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

        return chapters.isEmpty ? .failure(.empty("JSON \u{76ee}\u{5f55}\u{89e3}\u{6790}\u{7ed3}\u{679c}\u{4e3a}\u{7a7a}")) : .success(chapters)
    }
}

