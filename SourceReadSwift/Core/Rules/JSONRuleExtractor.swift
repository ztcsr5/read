import Foundation

final class JSONRuleDirectiveStore {
    private var values: [String: Any] = [:]

    func put(_ key: String, value: Any) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        values[clean] = value
    }

    func get(_ key: String) -> Any? {
        values[key.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}

struct JSONRuleExtractor {
    private enum DirectiveResult {
        case path(String)
        case value(Any)
    }

    private let directiveStore: JSONRuleDirectiveStore

    init(directiveStore: JSONRuleDirectiveStore = JSONRuleDirectiveStore()) {
        self.directiveStore = directiveStore
    }

    func list(from object: Any, rule: String?) -> [[String: Any]] {
        if let rule, let selected = value(from: object, path: rule) {
            if let array = selected as? [[String: Any]] {
                return array
            }
            if let array = selected as? [Any] {
                return array.compactMap { $0 as? [String: Any] }
            }
            if let dict = selected as? [String: Any] {
                return [dict]
            }
        }
        return collectDictionaries(object)
    }

    func string(from item: [String: Any], rule: String?, fallbackKeys: [String]) -> String? {
        if let rule, let value = value(from: item, path: rule) {
            let text = stringify(value)
            if !text.isEmpty {
                return text
            }
        }
        for key in fallbackKeys {
            if let value = item[key] {
                let text = stringify(value)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    func value(from object: Any, path rawPath: String) -> Any? {
        let transformed = splitTransform(rawPath)
        let directiveResult = applyDirectives(from: object, path: transformed.path)
        let operatorPath: String
        switch directiveResult {
        case .path(let path):
            operatorPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        case .value(let value):
            return applyTransform(transformed.transform, to: value)
        }
        guard !operatorPath.isEmpty else { return object }
        if let fallbackParts = RuleOperatorSplitter.split(operatorPath, separator: "||") {
            for part in fallbackParts {
                if let value = value(from: object, path: appendTransform(transformed.transform, to: part)) {
                    return value
                }
            }
            return nil
        }
        if let mergeParts = RuleOperatorSplitter.split(operatorPath, separator: "%%") {
            let values = mergeParts.compactMap { valueForSinglePath(from: object, path: normalize($0)) }
            let flattened = values.flatMap { value -> [Any] in
                if let array = value as? [Any] { return array }
                return [value]
            }
            return flattened.isEmpty ? nil : applyTransform(transformed.transform, to: flattened)
        }
        let path = normalize(operatorPath)
        guard !path.isEmpty else { return object }
        if let value = valueForSinglePath(from: object, path: path) {
            return applyTransform(transformed.transform, to: value)
        }
        return nil
    }

    private func applyDirectives(from object: Any, path: String) -> DirectiveResult {
        var output = path
        for directive in extractPutDirectives(from: output) {
            if let value = value(from: object, path: directive.valueRule) {
                directiveStore.put(directive.key, value: value)
            }
        }
        output = removePutDirectives(from: output)
        let directOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = directGetKey(from: directOutput), let value = directiveStore.get(key) {
            return .value(value)
        }
        output = replaceGetDirectives(in: output)

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return .path(trimmed)
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
            output.replaceSubrange(fullRange, with: stringify(directiveStore.get(key) ?? ""))
        }
        return output
    }

    private func directGetKey(from rule: String) -> String? {
        let lower = rule.lowercased()
        guard lower.hasPrefix("@get:") else { return nil }
        if lower.hasPrefix("@get:{"), rule.hasSuffix("}") {
            return String(rule.dropFirst(6).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(rule.dropFirst(5))
            .components(separatedBy: CharacterSet(charactersIn: "@#"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendTransform(_ transform: (pattern: String, replacement: String)?, to path: String) -> String {
        guard let transform else { return path }
        return "\(path)##\(transform.pattern)##\(transform.replacement)"
    }

    private func valueForSinglePath(from object: Any, path: String) -> Any? {
        var current: Any? = object
        let parts = tokenize(path)

        for part in parts {
            guard let existing = current else { return nil }
            if let dict = existing as? [String: Any] {
                current = dict[part] ?? dict[part.lowercased()] ?? dict[part.uppercased()]
            } else if let array = existing as? [Any], let index = Int(part) {
                let resolvedIndex = index < 0 ? array.count + index : index
                guard array.indices.contains(resolvedIndex) else { return nil }
                current = array[resolvedIndex]
            } else if let array = existing as? [Any], part == "*" {
                current = array
            } else if let array = existing as? [Any] {
                let mapped = array.compactMap { element -> Any? in
                    guard let dict = element as? [String: Any] else { return nil }
                    return dict[part] ?? dict[part.lowercased()] ?? dict[part.uppercased()]
                }
                current = mapped.reduce(into: [Any]()) { result, value in
                    if let array = value as? [Any] {
                        result.append(contentsOf: array)
                    } else {
                        result.append(value)
                    }
                }
            } else {
                return nil
            }
        }
        return current
    }

    private func tokenize(_ path: String) -> [String] {
        path
            .components(separatedBy: ".")
            .flatMap { part in
                part
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "/")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalize(_ rule: String) -> String {
        var output = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        output = output
            .replacingOccurrences(of: #"(?i)@put:\{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)@get:\{([^}]*)\}"#, with: "$1", options: .regularExpression)
        if output.hasPrefix("$.") {
            output.removeFirst(2)
        }
        if output.hasPrefix("$") {
            output.removeFirst()
        }
        if output.hasPrefix("@") {
            output.removeFirst()
        }
        if output.contains("&&") {
            output = output
                .components(separatedBy: "&&")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("@") }
                .joined(separator: ".")
        }
        if let atIndex = output.lastIndex(of: "@"), atIndex != output.startIndex {
            output.replaceSubrange(atIndex...atIndex, with: ".")
        }
        output = output.replacingOccurrences(of: #"\[['"]?([^'"\]]+)['"]?\]"#, with: ".$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\[(-?\d+)\]"#, with: ".$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\[\*\]"#, with: ".*", options: .regularExpression)
        return output.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func splitTransform(_ rawRule: String) -> (path: String, transform: (pattern: String, replacement: String)?) {
        let parts = rawRule.components(separatedBy: "##")
        guard parts.count >= 3 else {
            return (rawRule, nil)
        }
        return (
            parts[0],
            (
                pattern: parts[1],
                replacement: parts.dropFirst(2).joined(separator: "##")
            )
        )
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

    private func applyTransform(_ transform: (pattern: String, replacement: String)?, to value: Any) -> Any {
        guard let transform else { return value }
        if let array = value as? [Any] {
            return array.map { applyTransform(transform, to: $0) }
        }
        let text = stringify(value)
        return text.replacingOccurrences(
            of: transform.pattern,
            with: transform.replacement,
            options: .regularExpression
        )
    }

    private func collectDictionaries(_ object: Any) -> [[String: Any]] {
        if let dict = object as? [String: Any] {
            var result = [dict]
            for value in dict.values {
                result.append(contentsOf: collectDictionaries(value))
            }
            return result
        }
        if let array = object as? [Any] {
            return array.flatMap { collectDictionaries($0) }
        }
        return []
    }

    private func stringify(_ value: Any) -> String {
        if let array = value as? [Any] {
            return array.map { stringify($0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text == "<null>" ? "" : text
    }
}
