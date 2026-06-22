import Foundation

struct PurifyRuleEvaluator {
    static func apply(rule: String, to text: String) -> String {
        let lines = rule
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return apply(rules: lines.isEmpty ? [rule] : lines, to: text)
    }

    static func apply(rules: [String], to text: String) -> String {
        rules.reduce(text) { output, item in
            let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return output }

            if clean.contains("##") {
                let parts = clean.components(separatedBy: "##")
                return replaceRegex(
                    pattern: parts.first ?? "",
                    replacement: parts.dropFirst().first ?? "",
                    in: output
                )
            }
            return replaceRegex(pattern: clean, replacement: "", in: output)
        }
    }

    private static func replaceRegex(pattern: String, replacement: String, in text: String) -> String {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
