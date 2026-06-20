import Foundation
import SwiftSoup

struct HtmlRuleExtractor {
    func select(_ html: String, baseUrl: URL, listRule: String) throws -> [Element] {
        let document = try SwiftSoup.parse(html, baseUrl.absoluteString)
        return try document.select(cleanCSS(listRule)).array()
    }

    func value(from root: Element, rule: String?, fallback: String? = nil, baseUrl: URL? = nil) throws -> String {
        let selectedRule = rule ?? fallback
        guard let selectedRule, !selectedRule.isEmpty else { return "" }
        let parts = selectedRule.components(separatedBy: "@")
        let selector = cleanCSS(parts.first ?? "")
        let target = selector.isEmpty ? root : try root.select(selector).first() ?? root
        let attr = parts.dropFirst().first ?? "text"
        let value: String
        if attr == "text" {
            value = try target.text()
        } else if attr == "html" {
            value = try target.html()
        } else {
            value = try target.attr(attr)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["href", "src", "url"].contains(attr), let baseUrl {
            return absolutize(trimmed, base: baseUrl)
        }
        return trimmed
    }

    func firstRule(_ rule: SourceRule?, keys: [String]) -> String? {
        guard let rule else { return nil }
        for key in keys {
            if let value = rule.fields[key], !value.isEmpty {
                return value
            }
        }
        return rule.raw
    }

    func cleanCSS(_ rule: String) -> String {
        rule
            .replacingOccurrences(of: "&&", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func absolutize(_ text: String, base: URL) -> String {
        if let url = URL(string: text), url.scheme != nil {
            return url.absoluteString
        }
        return URL(string: text, relativeTo: base)?.absoluteURL.absoluteString ?? text
    }
}

