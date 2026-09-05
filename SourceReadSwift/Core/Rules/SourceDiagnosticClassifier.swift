import Foundation

/// Converts low-level source failures into actionable states shown in the source manager.
/// This is intentionally deterministic so batch diagnostics and XCTest use the same policy.
enum SourceDiagnosticClassifier {
    static func kind(
        message: String,
        stage: String,
        resultCount: Int = 0,
        contentIsEmpty: Bool = false
    ) -> SourceDiagnosticFailureKind {
        let value = "\(stage) \(message)".lowercased()
        if containsAny(value, ["测试关键词为空", "empty keyword", "invalid input"]) {
            return .invalidInput
        }
        if containsAny(value, ["cloudflare", "cf-chl", "challenge-platform", "captcha", "人机验证", "安全验证", "验证页面"]) {
            return .verification
        }
        if containsAny(value, ["401", "unauthorized", "未登录", "登录后", "cookie", "需要登录", "session expired", "请先登录"]) {
            return .authentication
        }
        if containsAny(value, ["403", "forbidden", "access denied", "blocked", "被拦截", "拒绝访问", "封禁", "rate limit", "429"]) {
            return .blocked
        }
        if containsAny(value, ["timeout", "timed out", "超时"]) {
            return .timeout
        }
        if contentIsEmpty || containsAny(value, ["empty", "为空", "解析为空", "没有识别到"]) {
            return .emptyResult
        }
        if containsAny(value, ["unsupported", "不支持", "未实现"]) {
            return .unsupported
        }
        if containsAny(value, ["javascript", "js error", "脚本", "exception"]) {
            return .javascript
        }
        if containsAny(value, ["parse", "parser", "rule", "解析", "规则", "jsonpath", "xpath", "selector"]) {
            return .parsing
        }
        if resultCount > 0 { return .unknown }
        return .network
    }

    static func kind(error: SourceEngineError, stage: String) -> SourceDiagnosticFailureKind {
        switch error {
        case .unsupported(let message):
            let detected = kind(message: message, stage: stage)
            return detected == .network ? .unsupported : detected
        case .invalidSource(let message):
            return containsAny(message.lowercased(), ["关键词为空", "empty keyword"]) ? .invalidInput : .invalidSource
        case .network(let message):
            let candidate = kind(message: message, stage: stage)
            return candidate == .network ? .network : candidate
        case .rule:
            return .parsing
        case .javascript:
            return .javascript
        case .blocked:
            return .blocked
        case .empty:
            return .emptyResult
        }
    }

    static func status(
        message: String,
        stage: String,
        resultCount: Int = 0,
        contentIsEmpty: Bool = false
    ) -> SourceHealthStatus {
        let value = "\(stage) \(message)".lowercased()
        switch kind(message: message, stage: stage, resultCount: resultCount, contentIsEmpty: contentIsEmpty) {
        case .verification:
            return .verificationRequired
        case .authentication:
            return .requiresLogin
        case .blocked:
            return .blocked
        case .emptyResult, .timeout:
            return .warning
        case .invalidSource, .invalidInput, .unsupported, .javascript, .parsing, .network, .cancelled, .unknown:
            if containsAny(value, ["invalid source", "无效书源", "书源 url"]) { return .failed }
            if resultCount > 0 { return .passed }
            return .failed
        }
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0.lowercased()) }
    }
}
