import Foundation

struct JSONRuleExtractor {
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
        let operatorPath = transformed.path.trimmingCharacters(in: .whitespacesAndNewlines)
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
