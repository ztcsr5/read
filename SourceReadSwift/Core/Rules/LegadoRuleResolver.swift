import Foundation

struct LegadoRuleResolver {
    func interpolate(_ text: String, keyword: String? = nil, page: Int? = nil, baseUrl: String? = nil) -> String {
        var output = text
        if let keyword {
            let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            output = output.replacingOccurrences(of: "{{key}}", with: encoded)
            output = output.replacingOccurrences(of: "{{keyword}}", with: encoded)
            output = output.replacingOccurrences(of: "{key}", with: encoded)
            output = output.replacingOccurrences(of: "{keyword}", with: encoded)
        }
        if let page {
            output = replaceArithmeticExpressions(in: output, page: page)
            output = output.replacingOccurrences(of: "{{page}}", with: String(page))
            output = output.replacingOccurrences(of: "{page}", with: String(page))
        }
        if let baseUrl {
            output = output.replacingOccurrences(of: "{{baseUrl}}", with: baseUrl)
            output = output.replacingOccurrences(of: "{baseUrl}", with: baseUrl)
        }
        return output
    }

    func splitLegadoRule(_ rule: String) -> [String] {
        rule
            .components(separatedBy: "&&")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func isJavaScriptRule(_ rule: String) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("@js:") || trimmed.hasPrefix("<js>") || trimmed.contains("java.")
    }

    private func replaceArithmeticExpressions(in text: String, page: Int) -> String {
        let pattern = "\\{\\{\\s*([^{}]+)\\s*\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var output = text
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let expression = nsText.substring(with: match.range(at: 1))
            guard let value = evaluatePageArithmetic(expression, page: page) else { continue }
            output = (output as NSString).replacingCharacters(in: match.range(at: 0), with: String(value))
        }
        return output
    }

    private func evaluatePageArithmetic(_ expression: String, page: Int) -> Int? {
        let replaced = expression
            .replacingOccurrences(of: "page", with: String(page))
            .replacingOccurrences(of: " ", with: "")
        guard !replaced.isEmpty,
              replaced.range(of: #"^[0-9+\-*/()]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        var parser = IntegerExpressionParser(replaced)
        return parser.parse()
    }
}

private struct IntegerExpressionParser {
    private let chars: [Character]
    private var index = 0

    init(_ text: String) {
        self.chars = Array(text)
    }

    mutating func parse() -> Int? {
        guard let value = parseExpression(), index == chars.count else { return nil }
        return value
    }

    private mutating func parseExpression() -> Int? {
        guard var value = parseTerm() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            advance()
            guard let rhs = parseTerm() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func parseTerm() -> Int? {
        guard var value = parseFactor() else { return nil }
        while let op = peek(), op == "*" || op == "/" {
            advance()
            guard let rhs = parseFactor() else { return nil }
            if op == "/" {
                guard rhs != 0 else { return nil }
                value /= rhs
            } else {
                value *= rhs
            }
        }
        return value
    }

    private mutating func parseFactor() -> Int? {
        guard let current = peek() else { return nil }
        if current == "(" {
            advance()
            guard let value = parseExpression(), peek() == ")" else { return nil }
            advance()
            return value
        }
        return parseNumber()
    }

    private mutating func parseNumber() -> Int? {
        let start = index
        while let current = peek(), current.isNumber {
            advance()
        }
        guard index > start else { return nil }
        return Int(String(chars[start..<index]))
    }

    private func peek() -> Character? {
        index < chars.count ? chars[index] : nil
    }

    private mutating func advance() {
        index += 1
    }
}
