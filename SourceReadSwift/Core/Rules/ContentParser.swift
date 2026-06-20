import Foundation

struct ContentParser {
    private let extractor = HtmlRuleExtractor()

    func parse(source: BookSource, chapter: BookChapter, response: SourceResponse) -> Result<ChapterContent, SourceEngineError> {
        guard let contentRule = extractor.firstRule(source.ruleContent, keys: ["content", "bookContent"]) else {
            return .failure(.rule("ruleContent.content 为空"))
        }

        do {
            let root = try extractor.select(response.body, baseUrl: response.url, listRule: "html").first
            guard let root else { return .failure(.empty("正文 HTML 为空")) }
            let raw = try extractor.value(from: root, rule: contentRule, fallback: nil, baseUrl: response.url)
            let paragraphs = splitParagraphs(raw)
            let next = try extractor.value(
                from: root,
                rule: extractor.firstRule(source.ruleContent, keys: ["nextContentUrl"]),
                fallback: nil,
                baseUrl: response.url
            ).nilIfEmpty
            return paragraphs.isEmpty
                ? .failure(.empty("正文解析结果为空"))
                : .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs, nextContentUrl: next))
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func splitParagraphs(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

