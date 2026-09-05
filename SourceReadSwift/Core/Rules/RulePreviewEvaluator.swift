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
        let evidence: Evidence
        let logs: [String]

        var matchedCount: Int { values.count }
        var hasMatches: Bool { !values.isEmpty }

        init(stage: Stage, values: [String], message: String, evidence: Evidence, logs: [String] = []) {
            self.stage = stage
            self.values = values
            self.message = message
            self.evidence = evidence
            self.logs = logs
        }
    }

    /// Deterministic evidence for the editor's offline preview.  Keeping the
    /// normalized byte counts and selected rule beside the output makes a
    /// preview explainable without opening a network inspector, and gives the
    /// UI the same kind of transport/normalization breadcrumbs as diagnostics.
    struct Evidence: Equatable, Sendable {
        let requestMethod: String
        let requestURL: String
        let inputByteCount: Int
        let normalizedByteCount: Int
        let format: String
        let selectedRule: String
        let normalizedResponse: String
        let parsedOutput: [String]
        let outputByteCount: Int
        let normalizationApplied: Bool
    }

    func preview(
        sample: String,
        ruleText: String,
        stage: Stage,
        baseURL: URL? = URL(string: "https://fixture.invalid/")
    ) -> Result {
        var logs = ["preview.start stage=\(stage.rawValue) inputBytes=\(sample.utf8.count)"]
        let normalizedSample = ResponseFormatDetector.normalizedBody(sample)
        if normalizedSample != sample {
            logs.append("response.normalized bytes=\(sample.utf8.count)->\(normalizedSample.utf8.count)")
        }
        let baseEvidence = Evidence(
            requestMethod: "LOCAL",
            requestURL: baseURL?.absoluteString ?? "fixture://local/",
            inputByteCount: sample.utf8.count,
            normalizedByteCount: normalizedSample.utf8.count,
            format: Self.format(of: normalizedSample),
            selectedRule: "",
            normalizedResponse: normalizedSample,
            parsedOutput: [],
            outputByteCount: 0,
            normalizationApplied: normalizedSample != sample
        )
        let trimmed = ruleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logs.append("rule.empty")
            return Result(stage: stage, values: [], message: "规则为空", evidence: baseEvidence, logs: logs)
        }
        let rule = parseRule(trimmed, preferredKeys: stage.preferredKeys)
        guard !rule.isEmpty else {
            logs.append("rule.no-executable-field")
            return Result(
                stage: stage,
                values: [],
                message: "规则对象没有可执行字段",
                evidence: baseEvidence.with(selectedRule: rule),
                logs: logs
            )
        }

        logs.append("rule.selected \(rule)")
        let evidence = baseEvidence.with(selectedRule: rule)

        let context = RuleExecutionContext()
        let analyzer = LegadoRuleAnalyzer(executionContext: context)
        let listValues = analyzer.stringList(content: normalizedSample, rule: rule, baseURL: baseURL)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !listValues.isEmpty {
            logs.append("extract.list count=\(listValues.count)")
            let message = listValues.joined(separator: "\n")
            return Result(
                stage: stage,
                values: listValues,
                message: message,
                evidence: evidence.with(outputByteCount: message.utf8.count, parsedOutput: listValues),
                logs: logs
            )
        }
        let scalar = analyzer.string(content: normalizedSample, rule: rule, baseURL: baseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if scalar.isEmpty {
            logs.append("extract.scalar empty")
            return Result(stage: stage, values: [], message: "未提取到结果", evidence: evidence, logs: logs)
        }
        logs.append("extract.scalar count=1")
        return Result(
            stage: stage,
            values: [scalar],
            message: scalar,
            evidence: evidence.with(outputByteCount: scalar.utf8.count, parsedOutput: [scalar]),
            logs: logs
        )
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

    private static func format(of body: String) -> String {
        if ResponseFormatDetector.jsonObject(from: body) != nil { return "JSON" }
        let lowercased = body.lowercased()
        if lowercased.contains("<html") || lowercased.contains("<div") || lowercased.contains("<article") {
            return "HTML"
        }
        return "文本"
    }
}

private extension RulePreviewEvaluator.Evidence {
    func with(
        selectedRule: String? = nil,
        outputByteCount: Int? = nil,
        parsedOutput: [String]? = nil
    ) -> Self {
        Self(
            requestMethod: requestMethod,
            requestURL: requestURL,
            inputByteCount: inputByteCount,
            normalizedByteCount: normalizedByteCount,
            format: format,
            selectedRule: selectedRule ?? self.selectedRule,
            normalizedResponse: normalizedResponse,
            parsedOutput: parsedOutput ?? self.parsedOutput,
            outputByteCount: outputByteCount ?? self.outputByteCount,
            normalizationApplied: normalizationApplied
        )
    }
}
