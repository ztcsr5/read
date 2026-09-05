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
        value = stripKnownWrapper(from: value)
        if let object = parseJSON(value) { return object }

        // A few legacy endpoints HTML-escape the JSON while still returning
        // it as text/html. Decode only the standard entity forms and retry;
        // ordinary HTML remains a non-JSON response.
        let unescaped = decodeHTMLEntities(value)
        if unescaped != value, let object = parseJSON(unescaped) { return object }

        // Some APIs return application/x-www-form-urlencoded envelopes such
        // as `data=%7B...%7D`. Percent-decode only when the decoded payload is
        // itself a balanced JSON value, avoiding accidental query decoding.
        if let decoded = value.removingPercentEncoding, decoded != value {
            if let object = parseJSON(decoded) { return object }
            // Form/query envelopes often keep a stable key in front of the
            // encoded payload (`data=%7B...%7D` or `json=%5B...%5D`).
            let candidates = decoded
                .split(separator: "&", omittingEmptySubsequences: true)
                .compactMap { part -> String? in
                    guard let equals = part.firstIndex(of: "=") else { return nil }
                    return String(part[part.index(after: equals)...])
                }
            for candidate in candidates {
                if let object = parseJSON(candidate) { return object }
            }
        }
        return nil
    }

    private static func parseJSON(_ value: String) -> Any? {
        let candidate = normalizedBody(value)
        if let data = candidate.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return object
        }
        return firstBalancedJSONValue(in: candidate)
    }

    /// Removes wrappers commonly emitted by JSONP and JavaScript bootstrap
    /// endpoints while keeping extraction conservative. The balanced scanner
    /// ensures a prose prefix/suffix cannot be mistaken for source data.
    private static func stripKnownWrapper(from input: String) -> String {
        var value = normalizedBody(input)
        for prefix in xssiPrefixes where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.lowercased().hasPrefix("<pre"),
           let end = value.firstIndex(of: ">"),
           let close = value.range(of: "</pre>", options: .caseInsensitive) {
            value = String(value[value.index(after: end)..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func decodeHTMLEntities(_ input: String) -> String {
        var value = input
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        // Numeric entities occur in escaped JSON returned by older PHP
        // endpoints. Decode them without introducing a Foundation parser.
        let pattern = "&#(x[0-9A-Fa-f]+|[0-9]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: nsRange).reversed()
        for match in matches {
            guard let whole = Range(match.range, in: value),
                  let number = Range(match.range(at: 1), in: value) else { continue }
            let token = String(value[number])
            let radix = token.lowercased().hasPrefix("x") ? 16 : 10
            let digits = token.dropFirst(token.lowercased().hasPrefix("x") ? 1 : 0)
            guard let scalarValue = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else { continue }
            value.replaceSubrange(whole, with: String(scalar))
        }
        return value
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
