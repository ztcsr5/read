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
            return .failure(.rule("ruleToc.chapterList 为空"))
        }

        do {
            let elements = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: listRule)
            let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
            let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])

            let chapters = try elements.enumerated().compactMap { index, element -> BookChapter? in
                let title = try htmlExtractor.value(from: element, rule: nameRule, fallback: "a@text", baseUrl: response.url, variables: variables)
                let url = try htmlExtractor.value(from: element, rule: urlRule, fallback: "a@href", baseUrl: response.url, variables: variables)
                guard !title.isEmpty, !url.isEmpty else { return nil }
                return BookChapter(title: title, url: url, bookUrl: book.bookUrl, index: index, isVip: false)
            }
            return chapters.isEmpty ? .failure(.empty("目录解析结果为空")) : .success(chapters)
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<[BookChapter], SourceEngineError> {
        guard let data = response.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.rule("JSON 解析失败"))
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
        let listRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"])
        let items = jsonExtractor.list(from: object, rule: listRule, variables: variables)
        let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
        let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])

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

        return chapters.isEmpty ? .failure(.empty("JSON 目录解析结果为空")) : .success(chapters)
    }
}

