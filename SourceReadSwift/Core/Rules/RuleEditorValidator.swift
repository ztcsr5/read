import Foundation

struct RuleValidationIssue: Equatable, Sendable {
    let field: String
    let message: String
}

struct RuleEditorValidator {
    func validate(source: BookSource, drafts: [String: String]) -> [RuleValidationIssue] {
        var issues: [RuleValidationIssue] = []
        if source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "bookSourceName", message: "书源名称不能为空"))
        }
        guard let url = URL(string: source.bookSourceUrl), url.scheme != nil else {
            issues.append(.init(field: "bookSourceUrl", message: "书源 URL 无效"))
            return issues
        }
        for (field, raw) in drafts {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if field == "searchUrl", !value.hasPrefix("@js:"), !value.contains("{{") {
                if URL(string: value) == nil {
                    issues.append(.init(field: field, message: "搜索 URL 不是有效地址或模板"))
                }
            }
            if field.hasPrefix("rule"), value.contains("<js>") && !value.contains("</js>") {
                issues.append(.init(field: field, message: "JS 规则缺少 </js> 结束标记"))
            }
            if value.hasPrefix("@xpath:") && value.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: field, message: "XPath 规则不能为空"))
            }
        }
        return issues
    }
}
