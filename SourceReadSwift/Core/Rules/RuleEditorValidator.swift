import Foundation
import JavaScriptCore

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
                guard let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      !value.contains(where: { $0.isWhitespace }) else {
                    issues.append(.init(field: field, message: "搜索 URL 不是有效地址或模板"))
                    continue
                }
            }
            if field.hasPrefix("rule") {
                issues.append(contentsOf: validateRuleText(value, field: field))
            }
        }
        return issues
    }

    private func validateRuleText(_ value: String, field: String) -> [RuleValidationIssue] {
        if value.contains("<js>") && !value.contains("</js>") {
            return [.init(field: field, message: "JS 规则缺少 </js> 结束标记")]
        }
        if value.hasPrefix("@xpath:"), value.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [.init(field: field, message: "XPath 规则不能为空")]
        }

        let executableRules: [String]
        if value.hasPrefix("{") || value.hasPrefix("[") {
            guard let data = value.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any] else {
                return [.init(field: field, message: "规则 JSON 格式错误，应为键值对象")]
            }
            let nonStringKeys = dictionary.compactMap { key, item in item is String ? nil : key }.sorted()
            if !nonStringKeys.isEmpty {
                return [.init(field: field, message: "规则字段必须是字符串：\(nonStringKeys.joined(separator: ", "))")]
            }
            executableRules = dictionary.values.compactMap { $0 as? String }
        } else {
            executableRules = [value]
        }

        for rule in executableRules {
            guard let script = javaScriptBody(rule) else { continue }
            let context = JSContext()
            let candidate = script.contains("return") ? "(function(){\(script)})" : script
            guard context?.checkScriptSyntax(candidate) == true else {
                let reason = context?.exception?.toString().trimmingCharacters(in: .whitespacesAndNewlines)
                return [.init(field: field, message: "JS 语法错误：\(reason?.nilIfEmpty ?? "无法解析")")]
            }
        }
        return []
    }

    private func javaScriptBody(_ rule: String) -> String? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@js:") {
            return String(trimmed.dropFirst(4))
        }
        if trimmed.hasPrefix("<js>"), trimmed.hasSuffix("</js>") {
            return String(trimmed.dropFirst(4).dropLast(5))
        }
        return nil
    }
}
