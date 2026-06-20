import Foundation

struct LegadoRuleResolver {
    func interpolate(_ text: String, keyword: String? = nil, page: Int? = nil, baseUrl: String? = nil) -> String {
        var output = text
        if let keyword {
            let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            output = output.replacingOccurrences(of: "{{key}}", with: encoded)
            output = output.replacingOccurrences(of: "{{keyword}}", with: encoded)
        }
        if let page {
            output = output.replacingOccurrences(of: "{{page}}", with: String(page))
        }
        if let baseUrl {
            output = output.replacingOccurrences(of: "{{baseUrl}}", with: baseUrl)
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
}

