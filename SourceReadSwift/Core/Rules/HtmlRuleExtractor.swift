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
        let alternatives = selectedRule
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for alternative in alternatives {
            let value = try valueForSingleRule(from: root, rule: alternative, baseUrl: baseUrl)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func valueForSingleRule(from root: Element, rule: String, baseUrl: URL?) throws -> String {
        let parts = rule.components(separatedBy: "@")
        let selector = cleanCSS(parts.first ?? "")
        let target = selector.isEmpty ? root : try root.select(selector).first() ?? root
        let attrRule = parts.dropFirst().first ?? "text"
        let attrParts = attrRule.components(separatedBy: "##")
        let attr = attrParts.first ?? "text"
        let value: String
        if attr == "text" {
            value = try target.text()
        } else if attr == "html" {
            value = try target.html()
        } else {
            value = try target.attr(attr)
        }
        let trimmed = applyRegexTransforms(attrParts.dropFirst(), to: value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ["href", "src", "url"].contains(attr), let baseUrl {
            return absolutize(trimmed, base: baseUrl)
        }
        return trimmed
    }

    private func applyRegexTransforms(_ rawParts: ArraySlice<String>, to value: String) -> String {
        let parts = Array(rawParts)
        guard !parts.isEmpty else { return value }
        var output = value
        var index = 0
        while index < parts.count {
            let pattern = parts[index]
            let replacement = index + 1 < parts.count ? parts[index + 1] : ""
            if !pattern.isEmpty {
                output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
            }
            index += 2
        }
        return output
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
