import Foundation
import SwiftSoup

struct RSSArticlePreview: Identifiable, Codable, Hashable, Sendable {
    var id: String { [sourceURL ?? "", title, link ?? "", pubDate ?? ""].joined(separator: "|") }
    let sourceURL: String?
    let title: String
    let link: String?
    let pubDate: String?
    let description: String?
    let imageURL: String?
    /// Raw feed-provided HTML (usually content:encoded). Kept separately from
    /// the plain-text summary so the reader can render the embedded article
    /// when the linked page is unavailable.
    let contentHTML: String?

    init(title: String, link: String?, pubDate: String?, description: String?, sourceURL: String? = nil, imageURL: String? = nil, contentHTML: String? = nil) {
        self.sourceURL = sourceURL
        self.title = title
        self.link = link
        self.pubDate = pubDate
        self.description = description
        self.imageURL = imageURL
        self.contentHTML = contentHTML
    }

    private enum CodingKeys: String, CodingKey { case sourceURL, title, link, pubDate, description, imageURL, contentHTML }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        title = try container.decode(String.self, forKey: .title)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        pubDate = try container.decodeIfPresent(String.self, forKey: .pubDate)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        contentHTML = try container.decodeIfPresent(String.self, forKey: .contentHTML)
    }
}

struct RSSFeedParser {
    func parseArticles(from text: String, sourceURL: String? = nil) -> [RSSArticlePreview] {
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
                link: firstLink(in: item, baseURL: sourceURL) ?? firstXMLValue(in: item, tags: ["guid"]),
                pubDate: firstXMLValue(in: item, tags: ["pubDate", "published", "updated", "dc:date"]),
                description: firstXMLValue(in: item, tags: ["description", "summary"]),
                sourceURL: sourceURL,
                imageURL: firstImageURL(in: item, baseURL: sourceURL),
                contentHTML: firstRawXMLValue(in: item, tags: ["content:encoded", "content"])
            )
        }
    }

    private func firstImageURL(in text: String, baseURL: String?) -> String? {
        let patterns = [
            #"<enclosure[^>]+url=[\"']([^\"']+)[\"']"#,
            #"<media:content[^>]+url=[\"']([^\"']+)[\"']"#,
            #"<img[^>]+src=[\"']([^\"']+)[\"']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let base = baseURL.flatMap { URL(string: $0) }
            if let absolute = URL(string: value, relativeTo: base)?.absoluteURL.absoluteString {
                return absolute
            }
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Atom feeds commonly expose a self link before the browser-facing article
    /// link. Prefer an alternate HTML link and fall back to the first usable
    /// link so RSS text links retain their existing behaviour.
    private func firstLink(in text: String, baseURL: String?) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<link\b([^>]*)>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var candidates: [(priority: Int, value: String)] = []
        for match in regex.matches(in: text, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: text) else { continue }
            let attributes = String(text[attributesRange])
            if let href = attributeValue("href", in: attributes) {
                let rel = attributeValue("rel", in: attributes)?.lowercased()
                let type = attributeValue("type", in: attributes)?.lowercased()
                let relTokens = Set(rel?.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) ?? [])
                if relTokens.contains("self") || relTokens.contains("enclosure") { continue }
                var priority = 2
                if rel?.split(separator: " ").contains("alternate") == true { priority = 0 }
                if type == "text/html" { priority = min(priority, 0) }
                candidates.append((priority, resolveURL(href, baseURL: baseURL)))
            }
        }
        if let best = candidates.sorted(by: { $0.priority < $1.priority }).first {
            return best.value
        }
        guard let value = firstXMLValue(in: text, tags: ["link"]), !value.isEmpty else { return nil }
        return resolveURL(value, baseURL: baseURL)
    }

    private func attributeValue(_ name: String, in attributes: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?:^|\s)"# + escaped + #"\s*=\s*[\"']([^\"']+)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)),
              let valueRange = Range(match.range(at: 1), in: attributes) else { return nil }
        return String(attributes[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveURL(_ value: String, baseURL: String?) -> String {
        let trimmed = cleanFeedText(value)
        guard let base = baseURL.flatMap({ URL(string: $0) }),
              let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL else {
            return trimmed
        }
        return resolved.absoluteString
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

    private func firstRawXMLValue(in text: String, tags: [String]) -> String? {
        for tag in tags {
            let escaped = NSRegularExpression.escapedPattern(for: tag)
            let patterns = [
                "<\(escaped)(?:\\s[^>]*)?><!\\[CDATA\\[([\\s\\S]*?)\\]\\]></\(escaped)>",
                "<\(escaped)(?:\\s[^>]*)?>([\\s\\S]*?)</\(escaped)>"
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                      let valueRange = Range(match.range(at: 1), in: text) else { continue }
                let value = String(text[valueRange])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
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

struct RSSArticleContentParser {
    func parseParagraphs(from html: String) -> [String] {
        do {
            let document = try SwiftSoup.parse(html)
            let candidates = try document.select("article, main, .entry-content, .post-content, .article-content, body").array()
            let nodes: [Element]
            if let container = candidates.first {
                nodes = try container.select("h1, h2, h3, p, li, blockquote").array()
            } else {
                nodes = try document.select("h1, h2, h3, p, li, blockquote").array()
            }
            let paragraphs = try nodes.compactMap { node -> String? in
                let value = try node.text().trimmingCharacters(in: .whitespacesAndNewlines)
                return value.nilIfEmpty
            }
            if !paragraphs.isEmpty { return paragraphs }
            let fallback = try (candidates.first?.text() ?? document.text())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return [fallback].filter { !$0.isEmpty }
        } catch {
            return html
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
}
