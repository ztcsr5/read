import Foundation
import SwiftSoup

struct HtmlRuleExtractor {
    func select(_ html: String, baseUrl: URL, listRule: String) throws -> [Element] {
        let document = try SwiftSoup.parse(html, baseUrl.absoluteString)
        return try select(from: document, rule: listRule)
    }

    func value(from root: Element, rule: String?, fallback: String? = nil, baseUrl: URL? = nil) throws -> String {
        let selectedRule = rule ?? fallback
        guard let selectedRule, !selectedRule.isEmpty else { return "" }
        if let alternatives = RuleOperatorSplitter.split(selectedRule, separator: "||") {
            for alternative in alternatives {
                let value = try self.value(from: root, rule: alternative, fallback: nil, baseUrl: baseUrl)
                if !value.isEmpty {
                    return value
                }
            }
            return ""
        }

        if let mergeParts = RuleOperatorSplitter.split(selectedRule, separator: "%%") {
            let lists = try mergeParts
                .map { try valuesForSingleRule(from: root, rule: $0, baseUrl: baseUrl) }
                .filter { !$0.isEmpty }
            return interleave(lists).joined(separator: "\n")
        }

        return try valuesForSingleRule(from: root, rule: selectedRule, baseUrl: baseUrl).first ?? ""
    }

    private func valuesForSingleRule(from root: Element, rule: String, baseUrl: URL?) throws -> [String] {
        let split = XPathRuleTranslator.valueRule(rule) ?? splitSelectorAndAttribute(rule)
        let targets = try select(from: root, rule: split.selector)
        let attrParts = split.attribute.components(separatedBy: "##")
        let attr = attrParts.first ?? "text"
        if attr == "all" {
            let joined = try targets.map { try $0.text() }.joined(separator: "\n")
            let transformed = applyRegexTransforms(attrParts.dropFirst(), to: joined)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return transformed.isEmpty ? [] : [transformed]
        }
        return try targets.compactMap { target in
            let value = try attributeValue(from: target, attr: attr)
            let trimmed = applyRegexTransforms(attrParts.dropFirst(), to: value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ["href", "src", "url"].contains(attr), let baseUrl {
                let absolute = absolutize(trimmed, base: baseUrl)
                return absolute.isEmpty ? nil : absolute
            }
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func attributeValue(from target: Element, attr: String) throws -> String {
        let value: String
        if attr == "text" || attr == "text()" {
            value = try target.text()
        } else if attr == "ownText" || attr == "ownText()" {
            value = try target.ownText()
        } else if attr == "textNodes" {
            value = try target.ownText()
        } else if attr == "html" || attr == "html()" {
            value = try target.html()
        } else {
            value = try target.attr(attr)
        }
        return value
    }

    private func select(from root: Element, rule: String) throws -> [Element] {
        if let fallbackParts = RuleOperatorSplitter.split(rule, separator: "||") {
            for part in fallbackParts {
                let elements = try select(from: root, rule: part)
                if !elements.isEmpty {
                    return elements
                }
            }
            return []
        }
        if let mergeParts = RuleOperatorSplitter.split(rule, separator: "%%") {
            let lists = try mergeParts
                .map { try select(from: root, rule: $0) }
                .filter { !$0.isEmpty }
            return interleave(lists)
        }
        let selector = XPathRuleTranslator.selectorRule(rule) ?? cleanCSS(rule)
        guard !selector.isEmpty else { return [root] }
        let indexed = parseIndexedSelector(selector)
        let elements = try root.select(indexed.selector).array()
        guard let index = indexed.index else { return elements }
        let normalized = index >= 0 ? index : elements.count + index
        guard elements.indices.contains(normalized) else { return [] }
        return [elements[normalized]]
    }

    private func splitSelectorAndAttribute(_ rule: String) -> (selector: String, attribute: String) {
        let parts = rule.components(separatedBy: "@")
        guard parts.count > 1 else {
            return (rule, "text")
        }
        let selector = parts.dropLast().joined(separator: "@")
        let attribute = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "text"
        return (selector, attribute)
    }

    private func parseIndexedSelector(_ selector: String) -> (selector: String, index: Int?) {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^(.*?)(?:@(-?\d+)|:eq\((-?\d+)\))$"#) else {
            return (trimmed, nil)
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else {
            return (trimmed, nil)
        }
        let selectorRange = match.range(at: 1)
        let firstIndexRange = match.range(at: 2)
        let secondIndexRange = match.range(at: 3)
        guard let cssRange = Range(selectorRange, in: trimmed) else {
            return (trimmed, nil)
        }
        let rawIndex: String?
        if let range = Range(firstIndexRange, in: trimmed) {
            rawIndex = String(trimmed[range])
        } else if let range = Range(secondIndexRange, in: trimmed) {
            rawIndex = String(trimmed[range])
        } else {
            rawIndex = nil
        }
        return (String(trimmed[cssRange]).trimmingCharacters(in: .whitespacesAndNewlines), rawIndex.flatMap(Int.init))
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
        var output = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = output.lowercased()
        if lower.hasPrefix("@css:") {
            output = String(output.dropFirst(5))
        } else if lower.hasPrefix("css:") {
            output = String(output.dropFirst(4))
        }
        return output
            .replacingOccurrences(of: "&&", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func absolutize(_ text: String, base: URL) -> String {
        if let url = URL(string: text), url.scheme != nil {
            return url.absoluteString
        }
        return URL(string: text, relativeTo: base)?.absoluteURL.absoluteString ?? text
    }

    private func interleave<T>(_ lists: [[T]]) -> [T] {
        let maxCount = lists.map(\.count).max() ?? 0
        var output: [T] = []
        for index in 0..<maxCount {
            for list in lists where list.indices.contains(index) {
                output.append(list[index])
            }
        }
        return output
    }
}
