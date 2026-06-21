import Foundation

struct XPathRuleTranslator {
    static func valueRule(_ rawRule: String) -> (selector: String, attribute: String)? {
        let parts = rawRule.components(separatedBy: "##")
        guard let translated = translate(parts.first ?? rawRule) else { return nil }
        let suffix = parts.count > 1 ? "##" + parts.dropFirst().joined(separator: "##") : ""
        return (translated.selector, translated.attribute + suffix)
    }

    static func selectorRule(_ rawRule: String) -> String? {
        translate(rawRule)?.selector
    }

    private static func translate(_ rawRule: String) -> (selector: String, attribute: String)? {
        var rule = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = rule.lowercased()
        if lower.hasPrefix("@xpath:") {
            rule = String(rule.dropFirst(7))
        } else if lower.hasPrefix("xpath:") {
            rule = String(rule.dropFirst(6))
        }
        guard rule.hasPrefix("//") || rule.hasPrefix("/") else { return nil }

        var attribute = "text"
        if rule.hasSuffix("/text()") {
            rule.removeLast("/text()".count)
            attribute = "all"
        } else if rule.hasSuffix("/@href") {
            rule.removeLast("/@href".count)
            attribute = "href"
        } else if rule.hasSuffix("/@src") {
            rule.removeLast("/@src".count)
            attribute = "src"
        } else if rule.hasSuffix("/@content") {
            rule.removeLast("/@content".count)
            attribute = "content"
        } else if let attrRange = rule.range(of: #"/@([A-Za-z_][A-Za-z0-9_:\-]*)$"#, options: .regularExpression) {
            attribute = String(String(rule[attrRange]).dropFirst(2))
            rule.removeSubrange(attrRange)
        }

        let selector = cssSelector(from: rule)
        guard !selector.isEmpty else { return nil }
        return (selector, attribute)
    }

    private static func cssSelector(from xpath: String) -> String {
        let normalized = xpath
            .replacingOccurrences(of: #"^/+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
        let steps = normalized
            .components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." }
        return steps.compactMap(cssStep).joined(separator: " ")
    }

    private static func cssStep(_ rawStep: String) -> String? {
        if rawStep == "*" { return "*" }
        guard let tagRange = rawStep.range(of: #"^(?:[A-Za-z][A-Za-z0-9_\-]*|\*)"#, options: .regularExpression) else {
            return nil
        }
        let tag = String(rawStep[tagRange])
        let predicateText = rawStep[tagRange.upperBound...]
        var selector = tag
        var indexSuffix = ""

        for predicate in predicates(String(predicateText)) {
            if let fragment = cssPredicate(predicate) {
                selector += fragment
            } else if let index = indexPredicate(predicate) {
                indexSuffix = "@\(index)"
            }
        }
        return selector + indexSuffix
    }

    private static func predicates(_ text: String) -> [String] {
        var output: [String] = []
        var start: String.Index?
        var depth = 0
        for index in text.indices {
            let char = text[index]
            if char == "[" {
                if depth == 0 { start = text.index(after: index) }
                depth += 1
            } else if char == "]" {
                depth = max(0, depth - 1)
                if depth == 0, let start {
                    output.append(String(text[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return output
    }

    private static func cssPredicate(_ predicate: String) -> String? {
        if let value = capture(predicate, pattern: #"^@id\s*=\s*['"]([^'"]+)['"]$"#) {
            return "#\(escapeIdentifier(value))"
        }
        if let value = capture(predicate, pattern: #"^@class\s*=\s*['"]([^'"]+)['"]$"#) {
            return value
                .split(whereSeparator: { $0.isWhitespace })
                .map { ".\(escapeIdentifier(String($0)))" }
                .joined()
        }
        if let value = capture(predicate, pattern: #"^contains\(\s*@class\s*,\s*['"]([^'"]+)['"]\s*\)$"#) {
            return ".\(escapeIdentifier(value))"
        }
        if let match = capturePair(predicate, pattern: #"^@([A-Za-z_][A-Za-z0-9_:\-]*)\s*=\s*['"]([^'"]+)['"]$"#) {
            return "[\(match.0)=\"\(match.1)\"]"
        }
        if let attr = capture(predicate, pattern: #"^@([A-Za-z_][A-Za-z0-9_:\-]*)$"#) {
            return "[\(attr)]"
        }
        return nil
    }

    private static func indexPredicate(_ predicate: String) -> Int? {
        let trimmed = predicate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "last()" { return -1 }
        guard let oneBased = Int(trimmed), oneBased > 0 else { return nil }
        return oneBased - 1
    }

    private static func capture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private static func capturePair(_ text: String, pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 2,
              let firstRange = Range(match.range(at: 1), in: text),
              let secondRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[firstRange]), String(text[secondRange]))
    }

    private static func escapeIdentifier(_ value: String) -> String {
        value.replacingOccurrences(of: #"([^A-Za-z0-9_\-])"#, with: #"\\$1"#, options: .regularExpression)
    }
}
