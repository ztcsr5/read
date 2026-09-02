import Foundation

/// Converts low-level source failures into actionable states shown in the source manager.
/// This is intentionally deterministic so batch diagnostics and XCTest use the same policy.
enum SourceDiagnosticClassifier {
    static func status(
        message: String,
        stage: String,
        resultCount: Int = 0,
        contentIsEmpty: Bool = false
    ) -> SourceHealthStatus {
        let value = "\(stage) \(message)".lowercased()
        if containsAny(value, ["cloudflare", "cf-chl", "challenge-platform", "captcha", "人机验证", "安全验证", "验证页面"]) {
            return .verificationRequired
        }
        if containsAny(value, ["401", "unauthorized", "未登录", "登录后", "cookie", "需要登录", "session expired", "请先登录"]) {
            return .requiresLogin
        }
        if containsAny(value, ["403", "forbidden", "access denied", "blocked", "被拦截", "拒绝访问", "封禁", "rate limit", "429"]) {
            return .blocked
        }
        if contentIsEmpty || containsAny(value, ["empty", "为空", "解析为空", "没有识别到"]) {
            return .warning
        }
        if containsAny(value, ["timeout", "timed out", "超时"]) {
            return .warning
        }
        return resultCount > 0 ? .passed : .failed
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0.lowercased()) }
    }
}
