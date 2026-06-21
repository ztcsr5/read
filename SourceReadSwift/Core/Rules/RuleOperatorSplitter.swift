import Foundation

struct RuleOperatorSplitter {
    static func split(_ text: String, separator: String) -> [String]? {
        guard !separator.isEmpty else { return nil }
        var parts: [String] = []
        var buffer = ""
        var index = text.startIndex
        var quote: Character?
        var escaped = false
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while index < text.endIndex {
            let char = text[index]
            if let activeQuote = quote {
                buffer.append(char)
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == activeQuote {
                    quote = nil
                }
                index = text.index(after: index)
                continue
            }

            if char == "\"" || char == "'" {
                quote = char
                buffer.append(char)
                index = text.index(after: index)
                continue
            }
            switch char {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               text[index...].hasPrefix(separator) {
                parts.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer.removeAll()
                index = text.index(index, offsetBy: separator.count)
                continue
            }

            buffer.append(char)
            index = text.index(after: index)
        }

        parts.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        let filtered = parts.filter { !$0.isEmpty }
        return filtered.count > 1 ? filtered : nil
    }
}
