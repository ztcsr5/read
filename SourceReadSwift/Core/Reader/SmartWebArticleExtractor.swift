import Foundation
import SwiftSoup

struct SmartWebArticle: Equatable, Sendable {
    let title: String
    let paragraphs: [String]

    var text: String { paragraphs.joined(separator: "\n\n") }
}

/// Turns an arbitrary article page into a readable, native-text projection.
/// This is intentionally conservative: scripts, navigation and repeated
/// boilerplate are removed, while short paragraphs are retained in order.
enum SmartWebArticleExtractor {
    static func extract(html: String, fallbackTitle: String = "网页文章") -> SmartWebArticle {
        guard let document = try? SwiftSoup.parse(html) else {
            return SmartWebArticle(title: fallbackTitle, paragraphs: plainText(html))
        }
        for selector in ["script", "style", "noscript", "nav", "header", "footer", "form", "aside"] {
            try? document.select(selector).remove()
        }
        let title = (try? document.title())?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? fallbackTitle
        let candidates: [SwiftSoup.Element] = (try? Array(document.select("article, main, [class*=content], [class*=article], body"))) ?? []
        let root: SwiftSoup.Element? = candidates.first ?? ((try? document.body()) ?? nil)
        let blocks: [SwiftSoup.Element] = root.map { (try? Array($0.select("p, h1, h2, h3, li"))) ?? [] } ?? []
        let structured = blocks.compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        let rawText = root.flatMap { try? $0.text() } ?? ""
        let paragraphs = structured.isEmpty ? plainText(rawText) : deduplicated(structured)
        return SmartWebArticle(title: title, paragraphs: paragraphs)
    }

    private static func plainText(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "  ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
            .reduce(into: [String]()) { result, paragraph in
                if result.last != paragraph { result.append(paragraph) }
            }
    }

    private static func deduplicated(_ paragraphs: [String]) -> [String] {
        var seen = Set<String>()
        return paragraphs.filter { seen.insert($0).inserted }
    }
}
