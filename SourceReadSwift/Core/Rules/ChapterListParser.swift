import Foundation

struct ChapterListParser {
    private let extractor = HtmlRuleExtractor()

    func parse(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<[BookChapter], SourceEngineError> {
        guard let listRule = extractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"]) else {
            return .failure(.rule("ruleToc.chapterList 为空"))
        }

        do {
            let elements = try extractor.select(response.body, baseUrl: response.url, listRule: listRule)
            let nameRule = extractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
            let urlRule = extractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])

            let chapters = try elements.enumerated().compactMap { index, element -> BookChapter? in
                let title = try extractor.value(from: element, rule: nameRule, fallback: "a@text", baseUrl: response.url)
                let url = try extractor.value(from: element, rule: urlRule, fallback: "a@href", baseUrl: response.url)
                guard !title.isEmpty, !url.isEmpty else { return nil }
                return BookChapter(title: title, url: url, bookUrl: book.bookUrl, index: index, isVip: false)
            }
            return chapters.isEmpty ? .failure(.empty("目录解析结果为空")) : .success(chapters)
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }
}

