import Foundation

/// Detects JSON responses without trusting only the first non-whitespace byte.
///
/// A number of Legado sources return a JSON document with a UTF-8 BOM, an
/// incorrect `text/html` content type, or a short anti-bot prefix before the
/// actual payload.  Keeping this logic in one place makes search/detail/TOC
/// and content parsers agree on the same format decision.
enum ResponseFormatDetector {
    private static let xssiPrefixes = [
        ")]}',",
        ")]}'",
        "while(1);",
        "for(;;);"
    ]

    static func normalizedBody(_ body: String) -> String {
        var value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.unicodeScalars.first == "\u{FEFF}" {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    static func prefersJSON(body: String, headers: [String: String]) -> Bool {
        let normalized = normalizedBody(body)
        guard !normalized.isEmpty else { return false }
        let contentType = headers.first { key, _ in
            key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value.lowercased() ?? ""
        if contentType.contains("json") || contentType.contains("javascript") {
            return jsonObject(from: normalized) != nil
        }
        if jsonObject(from: normalized) != nil { return true }

        // Some endpoints prepend an anti-bot comment or XSSI guard.  Strip
        // only known guards, never arbitrary prose, before attempting JSON.
        for prefix in xssiPrefixes where normalized.hasPrefix(prefix) {
            let candidate = normalized.dropFirst(prefix.count)
                .drop(while: { $0 == "," || $0.isWhitespace })
            if jsonObject(from: String(candidate)) != nil { return true }
        }
        return false
    }

    static func looksLikeJSON(_ body: String) -> Bool {
        jsonObject(from: body) != nil
    }

    /// Parses JSON wrapped in a `<pre>` element, an XSSI guard, or a BOM.
    /// The extraction is deliberately conservative: only the first balanced
    /// object/array candidate is considered, so prose around a response is
    /// never silently treated as source data.
    static func jsonObject(from body: String) -> Any? {
        var value = normalizedBody(body)
        for prefix in xssiPrefixes where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.lowercased().hasPrefix("<pre"), let end = value.firstIndex(of: ">"), let close = value.range(of: "</pre>", options: .caseInsensitive) {
            value = String(value[value.index(after: end)..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let data = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return object
        }
        return firstBalancedJSONValue(in: value)
    }

    private static func firstBalancedJSONValue(in value: String) -> Any? {
        let characters = Array(value)
        for start in characters.indices where characters[start] == "{" || characters[start] == "[" {
            guard let end = balancedEnd(in: characters, start: start) else { continue }
            let candidate = String(characters[start...end])
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                continue
            }
            return object
        }
        return nil
    }

    private static func balancedEnd(in characters: [Character], start: Int) -> Int? {
        var stack: [Character] = []
        var inString = false
        var escaped = false
        for index in start..<characters.count {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
                continue
            }
            if character == "{" || character == "[" {
                stack.append(character)
                continue
            }
            if character == "}" || character == "]" {
                guard let opening = stack.popLast(),
                      (opening == "{" && character == "}") || (opening == "[" && character == "]") else {
                    return nil
                }
                if stack.isEmpty { return index }
            }
        }
        return nil
    }
}
