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
        let path = normalize(rawPath)
        guard !path.isEmpty else { return object }
        let candidates = path.components(separatedBy: "||").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for candidate in candidates {
            if let value = valueForSinglePath(from: object, path: candidate) {
                return value
            }
        }
        return nil
    }

    private func valueForSinglePath(from object: Any, path: String) -> Any? {
        var current: Any? = object
        let parts = path
            .components(separatedBy: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for part in parts {
            guard let existing = current else { return nil }
            if let dict = existing as? [String: Any] {
                current = dict[part] ?? dict[part.lowercased()] ?? dict[part.uppercased()]
            } else if let array = existing as? [Any], let index = Int(part), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
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
        return output.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
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
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text == "<null>" ? "" : text
    }
}

