import Foundation

struct ContentParser {
    private let htmlExtractor = HtmlRuleExtractor()
    private let jsonExtractor = JSONRuleExtractor()

    func parse(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String] = []
    ) -> Result<ChapterContent, SourceEngineError> {
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "{" || body.first == "[" {
            return parseJSON(source: source, chapter: chapter, response: response, globalPurifyRules: globalPurifyRules)
        }
        return parseHTML(source: source, chapter: chapter, response: response, globalPurifyRules: globalPurifyRules)
    }

    private func parseHTML(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String]
    ) -> Result<ChapterContent, SourceEngineError> {
        guard let contentRule = htmlExtractor.firstRule(source.ruleContent, keys: ["content", "bookContent"]) else {
            return .failure(.rule("ruleContent.content \u{4e3a}\u{7a7a}"))
        }

        do {
            let root = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html").first
            guard let root else { return .failure(.empty("\u{6b63}\u{6587} HTML \u{4e3a}\u{7a7a}")) }
            let raw = try htmlExtractor.value(from: root, rule: contentRule, fallback: nil, baseUrl: response.url)
            let cleaned = applyContentTransforms(raw, rule: source.ruleContent, globalPurifyRules: globalPurifyRules)
            let paragraphs = splitParagraphs(cleaned)
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

    private func parseJSON(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String]
    ) -> Result<ChapterContent, SourceEngineError> {
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
        let paragraphs = splitParagraphs(applyContentTransforms(content ?? "", rule: rule, globalPurifyRules: globalPurifyRules))
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
        normalizeContentText(text)
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizeContentText(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?i)</li\\s*>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "&nbsp;", with: " ")
        output = output.replacingOccurrences(of: "&amp;", with: "&")
        output = output.replacingOccurrences(of: "&lt;", with: "<")
        output = output.replacingOccurrences(of: "&gt;", with: ">")
        output = output.replacingOccurrences(of: "&quot;", with: "\"")
        return output
    }

    private func applyContentTransforms(_ text: String, rule: SourceRule?, globalPurifyRules: [String]) -> String {
        var output = text
        let transformKeys = ["replaceRegex", "replace", "purify", "purifyRegex"]
        for key in transformKeys {
            guard let value = rule?.fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            output = applyTransform(value, to: output)
        }
        for rule in globalPurifyRules {
            output = applyTransform(rule, to: output)
        }
        return output
    }

    private func applyTransform(_ rule: String, to text: String) -> String {
        var output = text
        let lines = rule
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let items = lines.isEmpty ? [rule] : lines
        for item in items {
            if item.contains("##") {
                let parts = item.components(separatedBy: "##")
                let pattern = parts.first ?? ""
                let replacement = parts.dropFirst().first ?? ""
                if !pattern.isEmpty {
                    output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
                }
            } else {
                output = output.replacingOccurrences(of: item, with: "", options: .regularExpression)
            }
        }
        return output
    }
}
