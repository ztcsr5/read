import Foundation

/// Result of normalizing an Android Legado JavaScript fragment for the
/// synchronous JavaScriptCore bridge used by SourceReadSwift.
///
/// The native network bridge is intentionally synchronous (JavaScriptCore
/// callbacks cannot safely block on Swift concurrency).  Android sources
/// commonly spell these same calls with `await`, `async` and Promise chains.
/// This normalizer removes only those execution keywords outside strings,
/// comments and regular-expression literals; the existing synchronous host
/// shims then execute the call immediately.
struct LegadoJavaScriptNormalization: Equatable, Hashable, Sendable {
    let originalScript: String
    let normalizedScript: String
    let features: [String]

    var changed: Bool { originalScript != normalizedScript }
}

enum LegadoJavaScriptCompatibility {
    static func normalize(_ script: String) -> LegadoJavaScriptNormalization {
        let unwrapped = unwrap(script)
        var features = Set<String>()
        let lexicalFeatures = detectFeatures(in: unwrapped)
        features.formUnion(lexicalFeatures)

        let normalized = stripExecutionKeywords(from: unwrapped, features: &features)
        if normalized != unwrapped { features.insert("sync-normalization") }
        return LegadoJavaScriptNormalization(
            originalScript: unwrapped,
            normalizedScript: normalized,
            features: features.sorted()
        )
    }

    private static func unwrap(_ script: String) -> String {
        var value = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@js:") {
            value = String(value.dropFirst(4))
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<js>"), value.hasSuffix("</js>") {
            let start = value.index(value.startIndex, offsetBy: 4)
            let end = value.index(value.endIndex, offsetBy: -5)
            value = String(value[start..<end])
        }
        return value
    }

    private static func detectFeatures(in source: String) -> Set<String> {
        var features = Set<String>()
        let visible = lexicalVisibleText(source)
        let lower = visible.lowercased()
        if containsToken(lower, "await") { features.insert("await") }
        if containsToken(lower, "async") { features.insert("async") }
        if containsToken(lower, "promise") { features.insert("promise") }
        if containsToken(lower, "globalthis") { features.insert("globalThis") }
        if containsToken(lower, "urlsearchparams") { features.insert("URLSearchParams") }
        if containsToken(lower, "queuemicrotask") { features.insert("queueMicrotask") }
        if containsToken(lower, "settimeout") { features.insert("setTimeout") }
        for name in ["ajax", "ajaxall", "post", "fetch", "connect", "importscript", "postform", "ajax_bytes"] {
            if lower.range(of: "java.\(name)") != nil { features.insert("java.\(name)") }
        }
        return features
    }

    private static func containsToken(_ source: String, _ token: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_$])\(NSRegularExpression.escapedPattern(for: token))(?![A-Za-z0-9_$])") else { return false }
        return regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)) != nil
    }

    /// Replaces strings/comments/regexes with whitespace so feature detection
    /// and keyword stripping can never alter literal data.
    private static func lexicalVisibleText(_ source: String) -> String {
        var output = Array(repeating: Character(" "), count: source.count)
        let chars = Array(source)
        var index = 0
        var state = 0 // 0 normal, 1 single, 2 double, 3 template, 4 line, 5 block, 6 regex
        var escaped = false
        var inClass = false
        var previousSignificant: Character?
        while index < chars.count {
            let c = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            switch state {
            case 0:
                if c == "'" { state = 1; output[index] = " " }
                else if c == "\"" { state = 2; output[index] = " " }
                else if c == "`" { state = 3; output[index] = " " }
                else if c == "/", next == "/" { state = 4; output[index] = " "; index += 1; output[index] = " " }
                else if c == "/", next == "*" { state = 5; output[index] = " "; index += 1; output[index] = " " }
                else if c == "/", isRegexStart(previousSignificant) { state = 6; output[index] = " " }
                else { output[index] = c; if !c.isWhitespace { previousSignificant = c } }
            case 1, 2, 3:
                output[index] = c.isNewline ? c : " "
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if (state == 1 && c == "'") || (state == 2 && c == "\"") || (state == 3 && c == "`") { state = 0 }
            case 4:
                output[index] = c.isNewline ? c : " "
                if c.isNewline { state = 0; previousSignificant = c }
            case 5:
                output[index] = c.isNewline ? c : " "
                if c == "*", next == "/" { index += 1; output[index] = " "; state = 0 }
            case 6:
                output[index] = c.isNewline ? c : " "
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "[" { inClass = true }
                else if c == "]" { inClass = false }
                else if c == "/", !inClass { state = 0; previousSignificant = c }
            default: break
            }
            index += 1
        }
        return String(output)
    }

    private static func stripExecutionKeywords(
        from source: String,
        features: inout Set<String>
    ) -> String {
        let chars = Array(source)
        var output = chars
        var index = 0
        var state = 0 // same lexical states as lexicalVisibleText
        var escaped = false
        var inClass = false
        var previousSignificant: Character?
        while index < chars.count {
            let c = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            switch state {
            case 0:
                if c == "'" { state = 1 }
                else if c == "\"" { state = 2 }
                else if c == "`" { state = 3 }
                else if c == "/", next == "/" { state = 4; index += 1 }
                else if c == "/", next == "*" { state = 5; index += 1 }
                else if c == "/", isRegexStart(previousSignificant) { state = 6 }
                else if isIdentifierStart(c) {
                    let start = index
                    var end = index + 1
                    while end < chars.count, isIdentifierPart(chars[end]) { end += 1 }
                    let word = String(chars[start..<end])
                    if word == "await" {
                        features.insert("await")
                        for position in start..<end { output[position] = " " }
                    } else if word == "async", shouldStripAsync(in: chars, end: end) {
                        features.insert("async")
                        for position in start..<end { output[position] = " " }
                    }
                    if !word.isEmpty { previousSignificant = word.last }
                    index = end - 1
                } else if !c.isWhitespace { previousSignificant = c }
            case 1, 2, 3:
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if (state == 1 && c == "'") || (state == 2 && c == "\"") || (state == 3 && c == "`") { state = 0 }
            case 4:
                if c.isNewline { state = 0; previousSignificant = c }
            case 5:
                if c == "*", next == "/" { index += 1; state = 0 }
            case 6:
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "[" { inClass = true }
                else if c == "]" { inClass = false }
                else if c == "/", !inClass { state = 0; previousSignificant = c }
            default: break
            }
            index += 1
        }
        return String(output)
    }

    private static func shouldStripAsync(in chars: [Character], end: Int) -> Bool {
        var position = end
        while position < chars.count, chars[position].isWhitespace { position += 1 }
        guard position < chars.count else { return false }
        if chars[position...].starts(with: Array("function")) {
            let endOfFunction = position + "function".count
            return endOfFunction == chars.count || !isIdentifierPart(chars[endOfFunction])
        }
        if chars[position] == "(" {
            var depth = 1
            position += 1
            while position < chars.count, depth > 0 {
                if chars[position] == "(" { depth += 1 }
                else if chars[position] == ")" { depth -= 1 }
                position += 1
            }
            while position < chars.count, chars[position].isWhitespace { position += 1 }
            return position + 1 < chars.count && chars[position] == "=" && chars[position + 1] == ">"
        }
        let start = position
        while position < chars.count, isIdentifierPart(chars[position]) { position += 1 }
        guard position > start else { return false }
        while position < chars.count, chars[position].isWhitespace { position += 1 }
        return position + 1 < chars.count && chars[position] == "=" && chars[position + 1] == ">"
    }

    private static func isRegexStart(_ previous: Character?) -> Bool {
        guard let previous else { return true }
        return "=([{,:;!&|?+-*%^~<>".contains(previous)
    }

    private static func isIdentifierStart(_ value: Character) -> Bool {
        value == "_" || value == "$" || value.isLetter
    }

    private static func isIdentifierPart(_ value: Character) -> Bool {
        isIdentifierStart(value) || value.isNumber
    }
}
