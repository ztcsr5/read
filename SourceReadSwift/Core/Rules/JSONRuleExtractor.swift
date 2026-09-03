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
    private let executionContext: RuleExecutionContext

    init(
        directiveStore: JSONRuleDirectiveStore = JSONRuleDirectiveStore(),
        executionContext: RuleExecutionContext = RuleExecutionContext()
    ) {
        self.directiveStore = directiveStore
        self.executionContext = executionContext
    }

    func list(from object: Any, rule: String?, variables: [String: Any] = [:]) -> [[String: Any]] {
        if let rule, let selected = value(from: object, path: rule, variables: variables) {
            if let array = selected as? [[String: Any]] {
                return array
            }
            if let array = selected as? [Any] {
                return array.compactMap { $0 as? [String: Any] }
            }
            if let dict = selected as? [String: Any] {
                return [dict]
            }
            // Legado's @js list rules commonly return JSON.stringify(...)
            // rather than a native JS array.  JavaScriptCore bridges that
            // result back to Swift as a String, so decode it before falling
            // back to recursive dictionary discovery.  This keeps JS and
            // JSON bookList rules behaviorally equivalent.
            if let text = selected as? String,
               let data = text.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) {
                if let array = decoded as? [[String: Any]] {
                    return array
                }
                if let array = decoded as? [Any] {
                    return array.compactMap { $0 as? [String: Any] }
                }
                if let dict = decoded as? [String: Any] {
                    return [dict]
                }
            }
        }
        return collectDictionaries(object)
    }

    func string(
        from item: [String: Any],
        rule: String?,
        fallbackKeys: [String],
        variables: [String: Any] = [:]
    ) -> String? {
        if let rule {
            let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            if LegadoRuleResolver().isJavaScriptRule(trimmed) {
                if let evaluated = evaluateJS(rule: trimmed, object: item, extraVariables: variables) {
                    return stringify(evaluated)
                }
            }
            if let value = value(from: item, path: rule, variables: variables) {
                let text = stringify(value)
                if !text.isEmpty {
                    return text
                }
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

    func value(from object: Any, path rawPath: String, variables: [String: Any] = [:]) -> Any? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if LegadoRuleResolver().isJavaScriptRule(trimmed) {
            return evaluateJS(rule: trimmed, object: object, extraVariables: variables)
        }

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
                if let value = value(from: object, path: appendTransform(transformed.transform, to: part), variables: variables) {
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
        walk(object, parts: tokenize(path), index: 0)
    }

    private func tokenize(_ path: String) -> [String] {
        // Keep JSONPath's recursive descent (`..name`), wildcard and filter
        // segments intact. A plain components(separatedBy:) loses the empty
        // segment that distinguishes `..` from `.`, making common Legado
        // rules such as `$..bookList[*]` impossible to evaluate.
        var parts: [String] = []
        var buffer = ""
        var index = path.startIndex
        func flush() {
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { parts.append(value) }
            buffer.removeAll(keepingCapacity: true)
        }
        while index < path.endIndex {
            let ch = path[index]
            if ch == "[" {
                flush()
                var depth = 1
                var quote: Character?
                var escaped = false
                var cursor = path.index(after: index)
                var token = ""
                while cursor < path.endIndex, depth > 0 {
                    let c = path[cursor]
                    if let q = quote {
                        token.append(c)
                        if escaped { escaped = false }
                        else if c == "\\" { escaped = true }
                        else if c == q { quote = nil }
                    } else if c == "\"" || c == "'" {
                        quote = c; token.append(c)
                    } else if c == "[" {
                        depth += 1; token.append(c)
                    } else if c == "]" {
                        depth -= 1
                        if depth > 0 { token.append(c) }
                    } else {
                        token.append(c)
                    }
                    cursor = path.index(after: cursor)
                }
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let unquoted = unquote(trimmed)
                    parts.append(unquoted == "*" ? "*" : (unquoted.hasPrefix("?") ? unquoted : unquoted))
                }
                index = cursor
                continue
            }
            if ch == "." || ch == "/" {
                flush()
                if ch == "." {
                    let next = path.index(after: index)
                    if next < path.endIndex, path[next] == "." {
                        parts.append("**")
                        index = path.index(after: next)
                        continue
                    }
                }
                index = path.index(after: index)
                continue
            }
            buffer.append(ch)
            index = path.index(after: index)
        }
        flush()
        return parts
    }

    private func walk(_ current: Any, parts: [String], index: Int) -> Any? {
        guard index < parts.count else { return current }
        let part = parts[index]

        if part == "**" {
            // Recursive descent: try the remainder at this node and then at
            // every child. This mirrors the subset used by Legado sources.
            var matches: [Any] = []
            if let direct = walk(current, parts: parts, index: index + 1) {
                appendFlattened(direct, to: &matches)
            }
            for child in children(of: current) {
                if let nested = walk(child, parts: parts, index: index) {
                    appendFlattened(nested, to: &matches)
                }
            }
            return matches.isEmpty ? nil : matches
        }

        if let filter = filterPredicate(part), let array = current as? [Any] {
            let filtered = array.filter { matchesPredicate($0, filter: filter) }
            return walk(filtered, parts: parts, index: index + 1)
        }

        if let dict = current as? [String: Any] {
            if part == "*" {
                let values = Array(dict.values)
                return walk(values, parts: parts, index: index + 1)
            }
            guard let value = lookup(dict, key: part) else { return nil }
            return walk(value, parts: parts, index: index + 1)
        }

        if let array = current as? [Any] {
            if part == "*" {
                return walk(array, parts: parts, index: index + 1)
            }
            if let number = Int(part) {
                let resolved = number < 0 ? array.count + number : number
                guard array.indices.contains(resolved) else { return nil }
                return walk(array[resolved], parts: parts, index: index + 1)
            }
            let mapped = array.compactMap { element -> Any? in
                guard let result = walk(element, parts: parts, index: index) else { return nil }
                return result
            }
            if mapped.isEmpty { return nil }
            var flattened: [Any] = []
            mapped.forEach { appendFlattened($0, to: &flattened) }
            return flattened
        }
        return nil
    }

    private func lookup(_ dict: [String: Any], key: String) -> Any? {
        dict[key] ?? dict[key.lowercased()] ?? dict[key.uppercased()]
    }

    private func children(of value: Any) -> [Any] {
        if let dict = value as? [String: Any] { return Array(dict.values) }
        if let array = value as? [Any] { return array }
        return []
    }

    private func appendFlattened(_ value: Any, to output: inout [Any]) {
        if let array = value as? [Any] { array.forEach { appendFlattened($0, to: &output) } }
        else { output.append(value) }
    }

    private func filterPredicate(_ part: String) -> (path: String, op: String?, expected: String?)? {
        guard part.hasPrefix("?(") && part.hasSuffix(")") else { return nil }
        let expression = String(part.dropFirst(2).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        for op in ["!=", "==", "=", ">=", "<=", ">", "<"] {
            if let range = expression.range(of: op) {
                return (String(expression[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), op, String(expression[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return (expression, nil, nil)
    }

    private func matchesPredicate(_ value: Any, filter: (path: String, op: String?, expected: String?)) -> Bool {
        let key = filter.path.replacingOccurrences(of: "@.", with: "")
        let actual: Any?
        if key.isEmpty || key == "@" { actual = value }
        else { actual = valueForSinglePath(from: value, path: key) }
        guard let actual else { return false }
        guard let op = filter.op, let expected = filter.expected else { return truthy(actual) }
        let lhs = stringify(actual)
        let rhs = unquote(expected)
        if let l = Double(lhs), let r = Double(rhs) {
            switch op { case "==", "=": return l == r; case "!=": return l != r; case ">": return l > r; case "<": return l < r; case ">=": return l >= r; case "<=": return l <= r; default: return false }
        }
        switch op { case "==", "=": return lhs == rhs; case "!=": return lhs != rhs; default: return false }
    }

    private func truthy(_ value: Any) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        if let text = value as? String { return !text.isEmpty && text.lowercased() != "false" }
        return true
    }

    private func normalize(_ rule: String) -> String {
        var output = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep filters intact while still normalizing Legado's `@field`
        // suffix. Returning early for JSONPath broke rules such as
        // `$.data.book@name`; the bracket transforms below do not consume
        // `[?()]` predicates, so both syntaxes can share this path.
        if output.hasPrefix("$..") {
            output.removeFirst() // `$..name` -> `..name`, tokenizer emits `**`.
            return output
        }
        if output.hasPrefix("$.") {
            output.removeFirst(2)
        } else if output.hasPrefix("$") {
            output.removeFirst()
        }
        output = output
            .replacingOccurrences(of: #"(?i)@put:\{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)@get:\{([^}]*)\}"#, with: "$1", options: .regularExpression)
        if output.hasPrefix("$..") {
            output.removeFirst()
        } else if output.hasPrefix("$.") {
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
        // `@` inside a JSONPath predicate denotes the current element and
        // must not be rewritten as Legado's `@field` suffix operator.
        if !output.contains("[?"),
           let atIndex = output.lastIndex(of: "@"), atIndex != output.startIndex {
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

    private func evaluateJS(
        rule: String,
        object: Any,
        extraVariables: [String: Any]
    ) -> Any? {
        var script = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4))
        } else if script.hasPrefix("<js>") && script.hasSuffix("</js>") {
            let start = script.index(script.startIndex, offsetBy: 4)
            let end = script.index(script.endIndex, offsetBy: -5)
            script = String(script[start..<end])
        }

        let source = extraVariables["source"] as? BookSource
        let runtime = JSCoreRuntime(ajaxHandler: { urlText in
            if let source {
                return SynchronousSourceLoader().load(urlText: urlText, source: source)
            }
            return ""
        }, executionContext: executionContext)

        var variables: [String: Any] = [
            "result": object
        ]

        if JSONSerialization.isValidJSONObject(object) {
            if let data = try? JSONSerialization.data(withJSONObject: object, options: []),
               let jsonStr = String(data: data, encoding: .utf8) {
                variables["html"] = jsonStr
            }
        } else {
            variables["html"] = stringify(object)
        }

        for (k, v) in extraVariables {
            variables[k] = v
        }

        let evaluated = runtime.evaluate(script, variables: variables)
        if case .failure(.javascript) = evaluated, script.contains("return") {
            if case .success(let val) = runtime.evaluate("(function(){\(script)})()", variables: variables) {
                return val
            }
        }
        if case .success(let val) = evaluated {
            return val
        }
        return nil
    }
}
