import Foundation
import SwiftSoup

/// Single dispatch point for Legado CSS, XPath, JSONPath and JavaScript rules.
/// A parser chain owns one analyzer so `put/get`, model variables and the current
/// document survive from search through detail, TOC and content evaluation.
final class LegadoRuleAnalyzer {
    let executionContext: RuleExecutionContext
    private let htmlExtractor: HtmlRuleExtractor
    private let jsonExtractor: JSONRuleExtractor

    init(executionContext: RuleExecutionContext = RuleExecutionContext()) {
        self.executionContext = executionContext
        self.htmlExtractor = HtmlRuleExtractor(executionContext: executionContext)
        self.jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
    }

    func setContent(_ content: String, baseURL: URL?, variables: [String: Any] = [:]) {
        executionContext.bind(variables)
        executionContext.setValue(content, for: "result")
        executionContext.setValue(content, for: "html")
        executionContext.setValue(baseURL?.absoluteString ?? "", for: "baseUrl")
    }

    func string(
        content: String,
        rule: String?,
        baseURL: URL?,
        variables: [String: Any] = [:]
    ) -> String {
        guard let rule = rule?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else { return "" }
        setContent(content, baseURL: baseURL, variables: variables)
        if LegadoRuleResolver().isJavaScriptRule(rule) {
            return evaluateJavaScript(rule, variables: variables)
        }
        if let json = jsonObject(content) {
            return stringify(jsonExtractor.value(from: json, path: rule, variables: variables))
        }
        do {
            let root = try SwiftSoup.parse(content, baseURL?.absoluteString ?? "http://localhost/")
            return try htmlExtractor.value(from: root, rule: rule, baseUrl: baseURL, variables: variables)
        } catch {
            executionContext.log("RuleAnalyzer string failed: \(error.localizedDescription)")
            return ""
        }
    }

    func stringList(
        content: String,
        rule: String?,
        baseURL: URL?,
        variables: [String: Any] = [:]
    ) -> [String] {
        guard let rule = rule?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else { return [] }
        setContent(content, baseURL: baseURL, variables: variables)
        if LegadoRuleResolver().isJavaScriptRule(rule) {
            let value = evaluateJavaScript(rule, variables: variables)
            if let data = value.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return list.map(stringify).filter { !$0.isEmpty }
            }
            return value.isEmpty ? [] : [value]
        }
        if let json = jsonObject(content), let value = jsonExtractor.value(from: json, path: rule, variables: variables) {
            if let list = value as? [Any] { return list.map(stringify).filter { !$0.isEmpty } }
            let text = stringify(value)
            return text.isEmpty ? [] : [text]
        }
        do {
            let root = try SwiftSoup.parse(content, baseURL?.absoluteString ?? "http://localhost/")
            let value = try htmlExtractor.value(from: root, rule: rule, baseUrl: baseURL, variables: variables)
            return value.components(separatedBy: "\n").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        } catch {
            executionContext.log("RuleAnalyzer list failed: \(error.localizedDescription)")
            return []
        }
    }

    func elements(content: String, rule: String, baseURL: URL?, variables: [String: Any] = [:]) -> [Element] {
        setContent(content, baseURL: baseURL, variables: variables)
        do {
            let root = try SwiftSoup.parse(content, baseURL?.absoluteString ?? "http://localhost/")
            return try htmlExtractor.select(from: root, rule: rule, baseUrl: baseURL)
        } catch {
            executionContext.log("RuleAnalyzer elements failed: \(error.localizedDescription)")
            return []
        }
    }

    private func evaluateJavaScript(_ rawRule: String, variables: [String: Any]) -> String {
        var script = rawRule
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4))
        } else if script.hasPrefix("<js>"), script.hasSuffix("</js>") {
            script = String(script.dropFirst(4).dropLast(5))
        }
        let source = variables["source"] as? BookSource
        executionContext.responseHandler = { urlText in
            source.flatMap { SynchronousSourceLoader().loadResponse(urlText: urlText, source: $0) }
        }
        let runtime = JSCoreRuntime(ajaxHandler: { urlText in
            source.map { SynchronousSourceLoader().load(urlText: urlText, source: $0) } ?? ""
        }, executionContext: executionContext)
        var bindings = executionContext.snapshot()
        variables.forEach { bindings[$0.key] = $0.value }
        switch runtime.evaluate(script, variables: bindings) {
        case .success(let value): return value
        case .failure where script.contains("return"):
            if case .success(let value) = runtime.evaluate("(function(){\(script)})()", variables: bindings) { return value }
            return ""
        case .failure(let error):
            executionContext.log("RuleAnalyzer JS failed: \(error.localizedDescription)")
            return ""
        }
    }

    private func jsonObject(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return nil }
        return trimmed.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    private func stringify(_ value: Any?) -> String {
        RuleExecutionContext.bridgeString(value)
    }
}
