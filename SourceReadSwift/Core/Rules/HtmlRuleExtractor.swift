import Foundation
import SwiftSoup

final class RuleDirectiveStore {
    private var values: [String: String] = [:]

    func put(_ key: String, value: String) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        values[clean] = value
    }

    func get(_ key: String) -> String {
        values[key.trimmingCharacters(in: .whitespacesAndNewlines)] ?? ""
    }
}

struct HtmlRuleExtractor {
    private let directiveStore: RuleDirectiveStore

    init(directiveStore: RuleDirectiveStore = RuleDirectiveStore()) {
        self.directiveStore = directiveStore
    }

    func select(_ html: String, baseUrl: URL, listRule: String) throws -> [Element] {
        let document = try SwiftSoup.parse(html, baseUrl.absoluteString)
        return try select(from: document, rule: listRule, baseUrl: baseUrl)
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
        let materializedRule = try applyDirectives(root: root, rule: rule, baseUrl: baseUrl)
        if materializedRule.isEmpty {
            return []
        }
        if isDirectGetRule(rule) {
            return [materializedRule]
        }
        let split = XPathRuleTranslator.valueRule(materializedRule) ?? splitSelectorAndAttribute(materializedRule)
        let targets = try select(from: root, rule: split.selector, baseUrl: baseUrl)
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

    private func select(from root: Element, rule: String, baseUrl: URL? = nil) throws -> [Element] {
        let materializedRule = try applyDirectives(root: root, rule: rule, baseUrl: baseUrl)
        if materializedRule.isEmpty {
            return []
        }
        if let fallbackParts = RuleOperatorSplitter.split(materializedRule, separator: "||") {
            for part in fallbackParts {
                let elements = try select(from: root, rule: part, baseUrl: baseUrl)
                if !elements.isEmpty {
                    return elements
                }
            }
            return []
        }
        if let mergeParts = RuleOperatorSplitter.split(materializedRule, separator: "%%") {
            let lists = try mergeParts
                .map { try select(from: root, rule: $0, baseUrl: baseUrl) }
                .filter { !$0.isEmpty }
            return interleave(lists)
        }
        let selector = XPathRuleTranslator.selectorRule(materializedRule) ?? cleanCSS(materializedRule)
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

    private func applyDirectives(root: Element, rule: String, baseUrl: URL?) throws -> String {
        var output = rule
        let putDirectives = extractPutDirectives(from: output)
        for directive in putDirectives {
            let value = try value(from: root, rule: directive.valueRule, fallback: nil, baseUrl: baseUrl)
            directiveStore.put(directive.key, value: value)
        }
        output = removePutDirectives(from: output)
        output = replaceGetDirectives(in: output)
        if output.lowercased().hasPrefix("@get:") {
            let key = String(output.dropFirst(5))
                .components(separatedBy: CharacterSet(charactersIn: "@#"))
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return directiveStore.get(key)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isDirectGetRule(_ rule: String) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("@get:") else { return false }
        return !trimmed.contains("@text")
            && !trimmed.contains("@href")
            && !trimmed.contains("@src")
            && !trimmed.contains("@html")
            && !trimmed.contains("@ownText")
            && !trimmed.contains("##")
    }

    private func extractPutDirectives(from rule: String) -> [(key: String, valueRule: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)@put:\{([^}]*)\}"#) else { return [] }
        let range = NSRange(rule.startIndex..<rule.endIndex, in: rule)
        return regex.matches(in: rule, range: range).flatMap { match -> [(key: String, valueRule: String)] in
            guard let bodyRange = Range(match.range(at: 1), in: rule) else { return [] }
            return splitTopLevel(String(rule[bodyRange]), separator: ",")
                .compactMap { entry in
                    let parts = splitTopLevel(entry, separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    let key = unquote(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
                    let valueRule = unquote(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                    return key.isEmpty || valueRule.isEmpty ? nil : (key, valueRule)
                }
        }
    }

    private func removePutDirectives(from rule: String) -> String {
        rule.replacingOccurrences(of: #"(?i)@put:\{[^}]*\}"#, with: "", options: .regularExpression)
    }

    private func replaceGetDirectives(in rule: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)@get:\{([^}]*)\}"#) else { return rule }
        var output = rule
        let matches = regex.matches(in: rule, range: NSRange(rule.startIndex..<rule.endIndex, in: rule)).reversed()
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let keyRange = Range(match.range(at: 1), in: output) else { continue }
            let key = String(output[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            output.replaceSubrange(fullRange, with: directiveStore.get(key))
        }
        return output
    }

    private func unquote(_ value: String) -> String {
        var output = value
        if output.count >= 2,
           let first = output.first,
           let last = output.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            output.removeFirst()
            output.removeLast()
        }
        return output
    }

    private func splitTopLevel(_ value: String, separator: Character, maxSplits: Int = Int.max) -> [String] {
        var output: [String] = []
        var current = ""
        var quote: Character?
        var braceDepth = 0
        var bracketDepth = 0
        var parenDepth = 0
        var splits = 0
        var previous: Character?

        for character in value {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote, previous != "\\" {
                    quote = nil
                }
                previous = character
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "{":
                braceDepth += 1
                current.append(character)
            case "}":
                braceDepth = max(0, braceDepth - 1)
                current.append(character)
            case "[":
                bracketDepth += 1
                current.append(character)
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth = max(0, parenDepth - 1)
                current.append(character)
            default:
                if character == separator,
                   braceDepth == 0,
                   bracketDepth == 0,
                   parenDepth == 0,
                   splits < maxSplits {
                    output.append(current)
                    current = ""
                    splits += 1
                } else {
                    current.append(character)
                }
            }
            previous = character
        }
        output.append(current)
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
            .replacingOccurrences(of: #"(?i)@put:\{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)@get:\{[^}]*\}"#, with: "", options: .regularExpression)
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
