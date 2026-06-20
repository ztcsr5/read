import Foundation

struct ContentParser {
    private let htmlExtractor = HtmlRuleExtractor()
    private let jsonExtractor = JSONRuleExtractor()

    func parse(source: BookSource, chapter: BookChapter, response: SourceResponse) -> Result<ChapterContent, SourceEngineError> {
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "{" || body.first == "[" {
            return parseJSON(source: source, chapter: chapter, response: response)
        }
        return parseHTML(source: source, chapter: chapter, response: response)
    }

    private func parseHTML(source: BookSource, chapter: BookChapter, response: SourceResponse) -> Result<ChapterContent, SourceEngineError> {
        guard let contentRule = htmlExtractor.firstRule(source.ruleContent, keys: ["content", "bookContent"]) else {
            return .failure(.rule("ruleContent.content \u{4e3a}\u{7a7a}"))
        }

        do {
            let root = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html").first
            guard let root else { return .failure(.empty("\u{6b63}\u{6587} HTML \u{4e3a}\u{7a7a}")) }
            let raw = try htmlExtractor.value(from: root, rule: contentRule, fallback: nil, baseUrl: response.url)
            let paragraphs = splitParagraphs(raw)
            let next = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(source.ruleContent, keys: ["nextContentUrl"]),
                fallback: nil,
                baseUrl: response.url
            ).nilIfEmpty
            return paragraphs.isEmpty
                ? .failure(.empty("\u{6b63}\u{6587}\u{89e3}\u{6790}\u{7ed3}\u{679c}\u{4e3a}\u{7a7a}"))
                : .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs, nextContentUrl: next))
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, chapter: BookChapter, response: SourceResponse) -> Result<ChapterContent, SourceEngineError> {
        guard let data = response.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.rule("JSON \u{89e3}\u{6790}\u{5931}\u{8d25}"))
        }
        let rule = source.ruleContent
        let contentRule = htmlExtractor.firstRule(rule, keys: ["content", "bookContent"])
        let content: String?
        if let dict = object as? [String: Any] {
            content = jsonExtractor.string(
                from: dict,
                rule: contentRule,
                fallbackKeys: ["content", "bookContent", "text", "body"]
            )
        } else {
            content = nil
        }
        let paragraphs = splitParagraphs(content ?? "")
        let next: String?
        if let dict = object as? [String: Any] {
            next = jsonExtractor.string(
                from: dict,
                rule: htmlExtractor.firstRule(rule, keys: ["nextContentUrl"]),
                fallbackKeys: ["nextContentUrl", "nextUrl", "next"]
            ).map { htmlExtractor.absolutize($0, base: response.url) }
        } else {
            next = nil
        }
        return paragraphs.isEmpty
            ? .failure(.empty("JSON \u{6b63}\u{6587}\u{89e3}\u{6790}\u{7ed3}\u{679c}\u{4e3a}\u{7a7a}"))
            : .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs, nextContentUrl: next))
    }

    private func splitParagraphs(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
