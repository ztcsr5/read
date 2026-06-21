import Foundation

enum SourceImportInputKind: Equatable, Sendable {
    case empty
    case json
    case url
    case unsupportedScheme
    case unknown
}

struct SourceImportInput: Equatable, Sendable {
    let kind: SourceImportInputKind
    let value: String
}

struct SourceImportLinkParser {
    static func parse(_ input: String) -> SourceImportInput {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SourceImportInput(kind: .empty, value: "")
        }

        if looksLikeJSON(trimmed) {
            return SourceImportInput(kind: .json, value: trimmed)
        }

        if let importURL = extractImportURL(from: trimmed) {
            return SourceImportInput(kind: .url, value: importURL)
        }

        if containsImportScheme(trimmed) {
            return SourceImportInput(kind: .unsupportedScheme, value: trimmed)
        }

        if let sharedURL = extractHTTPURL(from: trimmed) {
            return SourceImportInput(kind: .url, value: sharedURL)
        }

        return SourceImportInput(kind: .unknown, value: trimmed)
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("{") || value.hasPrefix("[")
    }

    private static func containsImportScheme(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("yuedu://") || lower.contains("legado://")
    }

    private static func extractImportURL(from text: String) -> String? {
        guard let schemeRange = findImportSchemeRange(in: text) else { return nil }
        let tail = String(text[schemeRange.lowerBound...])
        let token = trimURLToken(tail)
        guard let components = URLComponents(string: token) else { return nil }
        let queryItems = components.queryItems ?? []
        for key in ["src", "url"] {
            if let value = queryItems.first(where: { $0.name.lowercased() == key })?.value,
               let normalized = normalizeExtractedURL(value) {
                return normalized
            }
        }
        return nil
    }

    private static func findImportSchemeRange(in text: String) -> Range<String.Index>? {
        if let range = text.range(of: "yuedu://", options: .caseInsensitive) {
            return range
        }
        if let range = text.range(of: "legado://", options: .caseInsensitive) {
            return range
        }
        return nil
    }

    private static func extractHTTPURL(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return normalizeExtractedURL(String(text[range]))
    }

    private static func normalizeExtractedURL(_ raw: String) -> String? {
        var value = raw.removingPercentEncoding ?? raw
        value = trimURLToken(value)
        guard value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") else {
            return nil
        }
        return value
    }

    private static func trimURLToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(trailingPunctuation))
    }

    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)])}>\"'\u{FF0C}\u{3002}\u{FF1B}\u{FF1A}\u{FF01}\u{FF1F}\u{FF09}\u{3011}\u{300B}\u{3001}")
}
