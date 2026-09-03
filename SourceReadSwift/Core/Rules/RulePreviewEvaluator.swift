import Foundation

/// Runs one draft rule against a local HTML/JSON sample without touching the
/// network or persistent source state. This keeps the editor's preview path
/// deterministic and makes rule debugging possible on-device/offline.
struct RulePreviewEvaluator {
    enum Stage: String, CaseIterable, Identifiable, Sendable {
        case search = "搜索"
        case detail = "详情"
        case toc = "目录"
        case content = "正文"

        var id: String { rawValue }

        var preferredKeys: [String] {
            switch self {
            case .search: return ["name", "bookName", "bookList", "list"]
            case .detail: return ["name", "bookName", "title"]
            case .toc: return ["chapterName", "chapterList", "name", "title"]
            case .content: return ["content", "text", "body"]
            }
        }
    }

    struct Result: Equatable, Sendable {
        let stage: Stage
        let values: [String]
        let message: String

        var matchedCount: Int { values.count }
        var hasMatches: Bool { !values.isEmpty }
    }

    func preview(
        sample: String,
        ruleText: String,
        stage: Stage,
        baseURL: URL? = URL(string: "https://fixture.invalid/")
    ) -> Result {
        let trimmed = ruleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(stage: stage, values: [], message: "规则为空")
        }
        let rule = parseRule(trimmed, preferredKeys: stage.preferredKeys)
        guard !rule.isEmpty else {
            return Result(stage: stage, values: [], message: "规则对象没有可执行字段")
        }

        let context = RuleExecutionContext()
        let analyzer = LegadoRuleAnalyzer(executionContext: context)
        let listValues = analyzer.stringList(content: sample, rule: rule, baseURL: baseURL)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !listValues.isEmpty {
            return Result(stage: stage, values: listValues, message: listValues.joined(separator: "\n"))
        }
        let scalar = analyzer.string(content: sample, rule: rule, baseURL: baseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if scalar.isEmpty {
            return Result(stage: stage, values: [], message: "未提取到结果")
        }
        return Result(stage: stage, values: [scalar], message: scalar)
    }

    func evaluate(
        sample: String,
        ruleText: String,
        stage: Stage,
        baseURL: URL? = URL(string: "https://fixture.invalid/")
    ) -> String {
        preview(sample: sample, ruleText: ruleText, stage: stage, baseURL: baseURL).message
    }

    private func parseRule(_ text: String, preferredKeys: [String]) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return text
        }
        for key in preferredKeys {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return object.values.compactMap { $0 as? String }.first ?? ""
    }
}
