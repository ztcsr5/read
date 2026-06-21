import Foundation

struct RSSArticlePreview: Identifiable, Hashable, Sendable {
    var id: String { [title, link ?? "", pubDate ?? ""].joined(separator: "|") }
    let title: String
    let link: String?
    let pubDate: String?
    let description: String?
}

struct RSSFeedParser {
    func parseArticles(from text: String) -> [RSSArticlePreview] {
        let itemPattern = text.range(of: "<entry", options: .caseInsensitive) == nil
            ? #"<item[\s\S]*?</item>"#
            : #"<entry[\s\S]*?</entry>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return itemRegex.matches(in: text, range: range).compactMap { match in
            guard let itemRange = Range(match.range, in: text) else { return nil }
            let item = String(text[itemRange])
            guard let title = firstXMLValue(in: item, tags: ["title"]) else { return nil }
            return RSSArticlePreview(
                title: title,
                link: firstXMLValue(in: item, tags: ["link", "guid"]),
                pubDate: firstXMLValue(in: item, tags: ["pubDate", "published", "updated"]),
                description: firstXMLValue(in: item, tags: ["description", "summary", "content"])
            )
        }
    }

    private func firstXMLValue(in text: String, tags: [String]) -> String? {
        for tag in tags {
            let escaped = NSRegularExpression.escapedPattern(for: tag)
            let patterns = [
                "<\(escaped)(?:\\s[^>]*)?><!\\[CDATA\\[([\\s\\S]*?)\\]\\]></\(escaped)>",
                "<\(escaped)(?:\\s[^>]*)?>([\\s\\S]*?)</\(escaped)>",
                "<\(escaped)(?:\\s[^>]*)?href=[\"']([^\"']+)[\"'][^>]*/?>"
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: text) else { continue }
                let value = cleanFeedText(String(text[valueRange]))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func cleanFeedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
