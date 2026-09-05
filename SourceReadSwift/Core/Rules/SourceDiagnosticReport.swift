import Foundation

/// A portable four-stage diagnostic result. The UI can render this model and
/// the same shape can be exported without scraping human-readable strings.
enum SourceDiagnosticStage: String, CaseIterable, Codable, Hashable, Sendable {
    case search
    case detail
    case toc
    case content

    var title: String {
        switch self {
        case .search: return "搜索"
        case .detail: return "详情"
        case .toc: return "目录"
        case .content: return "正文"
        }
    }
}

/// Stable machine-readable failure taxonomy used by batch diagnostics.  The
/// human-facing `failureClassification` string is intentionally preserved for
/// compatibility, while this code lets UI, exports and automation group the
/// same failure consistently across sources and locales.
enum SourceDiagnosticFailureKind: String, Codable, Hashable, Sendable {
    case invalidInput = "invalid-input"
    case invalidSource = "invalid-source"
    case network
    case timeout
    case parsing
    case emptyResult = "empty-result"
    case authentication
    case verification
    case blocked
    case unsupported
    case javascript
    case cancelled
    case unknown

    var isRetryable: Bool {
        switch self {
        case .network, .timeout, .verification:
            return true
        case .invalidInput, .invalidSource, .parsing, .emptyResult,
             .authentication, .blocked, .unsupported, .javascript,
             .cancelled, .unknown:
            return false
        }
    }
}

struct SourceDiagnosticStep: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let stage: SourceDiagnosticStage
    let status: SourceHealthStatus
    let requestSummary: String?
    let responseSummary: String?
    let matchCount: Int
    let elapsedMilliseconds: Int?
    let failureClassification: String?
    /// Normalized request/response metadata.  These fields are optional so
    /// reports written by older builds continue to decode unchanged.
    let requestMethod: String?
    let requestBody: String?
    let requestHeaders: [String: String]?
    let responseStatusCode: Int?
    let responseHeaders: [String: String]?
    let cookieSummary: String?
    let finalURL: String?
    let responseEncodedByteCount: Int?
    let responseDecodedByteCount: Int?
    let responseContentEncodings: [String]?
    let responseWasDecoded: Bool
    let javascript: [SourceJavaScriptEvidence]?
    let executionLogs: [String]?
    let retryCount: Int
    let failureCode: SourceDiagnosticFailureKind?
    let retryable: Bool

    private enum CodingKeys: String, CodingKey {
        case id, stage, status, requestSummary, responseSummary, matchCount,
             elapsedMilliseconds, failureClassification, requestMethod,
             requestBody, requestHeaders, responseStatusCode, responseHeaders,
             cookieSummary, finalURL, responseEncodedByteCount,
             responseDecodedByteCount, responseContentEncodings, responseWasDecoded,
             javascript, executionLogs, retryCount, failureCode, retryable
    }

    init(
        id: UUID = UUID(),
        stage: SourceDiagnosticStage,
        status: SourceHealthStatus,
        requestSummary: String? = nil,
        responseSummary: String? = nil,
        matchCount: Int = 0,
        elapsedMilliseconds: Int? = nil,
        failureClassification: String? = nil,
        requestMethod: String? = nil,
        requestBody: String? = nil,
        requestHeaders: [String: String]? = nil,
        responseStatusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        cookieSummary: String? = nil,
        finalURL: String? = nil,
        responseEncodedByteCount: Int? = nil,
        responseDecodedByteCount: Int? = nil,
        responseContentEncodings: [String]? = nil,
        responseWasDecoded: Bool = false,
        javascript: [SourceJavaScriptEvidence]? = nil,
        executionLogs: [String]? = nil,
        retryCount: Int = 0,
        failureCode: SourceDiagnosticFailureKind? = nil,
        retryable: Bool? = nil
    ) {
        self.id = id
        self.stage = stage
        self.status = status
        self.requestSummary = requestSummary
        self.responseSummary = responseSummary
        self.matchCount = max(matchCount, 0)
        self.elapsedMilliseconds = elapsedMilliseconds
        self.failureClassification = failureClassification
        self.requestMethod = requestMethod
        self.requestBody = requestBody.map(SourceDiagnosticRedactor.body)
        self.requestHeaders = requestHeaders.map(SourceDiagnosticRedactor.headers)
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders.map(SourceDiagnosticRedactor.headers)
        self.cookieSummary = cookieSummary.map(SourceDiagnosticRedactor.value)
        self.finalURL = finalURL
        self.responseEncodedByteCount = responseEncodedByteCount
        self.responseDecodedByteCount = responseDecodedByteCount
        self.responseContentEncodings = responseContentEncodings
        self.responseWasDecoded = responseWasDecoded
        self.javascript = javascript?.map(SourceDiagnosticRedactor.javascript)
        self.executionLogs = executionLogs?.map(SourceDiagnosticRedactor.log)
        self.retryCount = max(0, retryCount)
        self.failureCode = failureCode
        self.retryable = retryable ?? failureCode?.isRetryable ?? false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            stage: try container.decode(SourceDiagnosticStage.self, forKey: .stage),
            status: try container.decode(SourceHealthStatus.self, forKey: .status),
            requestSummary: try container.decodeIfPresent(String.self, forKey: .requestSummary),
            responseSummary: try container.decodeIfPresent(String.self, forKey: .responseSummary),
            matchCount: try container.decodeIfPresent(Int.self, forKey: .matchCount) ?? 0,
            elapsedMilliseconds: try container.decodeIfPresent(Int.self, forKey: .elapsedMilliseconds),
            failureClassification: try container.decodeIfPresent(String.self, forKey: .failureClassification),
            requestMethod: try container.decodeIfPresent(String.self, forKey: .requestMethod),
            requestBody: try container.decodeIfPresent(String.self, forKey: .requestBody),
            requestHeaders: try container.decodeIfPresent([String: String].self, forKey: .requestHeaders),
            responseStatusCode: try container.decodeIfPresent(Int.self, forKey: .responseStatusCode),
            responseHeaders: try container.decodeIfPresent([String: String].self, forKey: .responseHeaders),
            cookieSummary: try container.decodeIfPresent(String.self, forKey: .cookieSummary),
            finalURL: try container.decodeIfPresent(String.self, forKey: .finalURL),
            responseEncodedByteCount: try container.decodeIfPresent(Int.self, forKey: .responseEncodedByteCount),
            responseDecodedByteCount: try container.decodeIfPresent(Int.self, forKey: .responseDecodedByteCount),
            responseContentEncodings: try container.decodeIfPresent([String].self, forKey: .responseContentEncodings),
            responseWasDecoded: try container.decodeIfPresent(Bool.self, forKey: .responseWasDecoded) ?? false,
            javascript: try container.decodeIfPresent([SourceJavaScriptEvidence].self, forKey: .javascript),
            executionLogs: try container.decodeIfPresent([String].self, forKey: .executionLogs),
            retryCount: try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0,
            failureCode: try container.decodeIfPresent(SourceDiagnosticFailureKind.self, forKey: .failureCode),
            retryable: try container.decodeIfPresent(Bool.self, forKey: .retryable)
        )
    }
}

struct SourceDiagnosticReport: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceName: String
    let sourceURL: String
    let keyword: String
    let startedAt: Date
    let steps: [SourceDiagnosticStep]

    init(
        id: UUID = UUID(),
        sourceName: String,
        sourceURL: String,
        keyword: String,
        startedAt: Date = Date(),
        steps: [SourceDiagnosticStep] = []
    ) {
        self.id = id
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.keyword = keyword
        self.startedAt = startedAt
        self.steps = steps.sorted { lhs, rhs in
            SourceDiagnosticStage.allCases.firstIndex(of: lhs.stage)! < SourceDiagnosticStage.allCases.firstIndex(of: rhs.stage)!
        }
    }

    var overallStatus: SourceHealthStatus {
        if steps.contains(where: { $0.status == .blocked }) { return .blocked }
        if steps.contains(where: { $0.status == .verificationRequired }) { return .verificationRequired }
        if steps.contains(where: { $0.status == .requiresLogin }) { return .requiresLogin }
        if steps.contains(where: { $0.status == .failed }) { return .failed }
        if steps.contains(where: { $0.status == .warning }) { return .warning }
        return steps.isEmpty ? .warning : .passed
    }

    var firstFailure: SourceDiagnosticStep? {
        steps.first { $0.status != .passed }
    }

    static func prioritized(_ reports: [SourceDiagnosticReport]) -> [SourceDiagnosticReport] {
        reports.sorted { lhs, rhs in
            let leftRank = statusRank(lhs.overallStatus)
            let rightRank = statusRank(rhs.overallStatus)
            if leftRank != rightRank { return leftRank < rightRank }
            let leftElapsed = lhs.steps.compactMap(\.elapsedMilliseconds).max() ?? 0
            let rightElapsed = rhs.steps.compactMap(\.elapsedMilliseconds).max() ?? 0
            if leftElapsed != rightElapsed { return leftElapsed > rightElapsed }
            return lhs.sourceName.localizedCaseInsensitiveCompare(rhs.sourceName) == .orderedAscending
        }
    }

    private static func statusRank(_ status: SourceHealthStatus) -> Int {
        switch status {
        case .failed, .blocked, .verificationRequired, .requiresLogin: return 0
        case .warning: return 1
        case .passed: return 2
        }
    }
}

/// Batch diagnostics are exported to users, so never persist credential-like
/// header values in a report.  Keep the key and presence visible for source
/// debugging while replacing the secret value with a stable marker.
enum SourceDiagnosticRedactor {
    private static let sensitiveKeys: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie",
        "x-api-key", "api-key", "apikey", "token", "access-token",
        "refresh-token", "password", "passwd", "secret"
    ]

    static func headers(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, item in
            let key = item.key
            result[key] = isSensitive(key) ? "<redacted>" : item.value
        }
    }

    static func value(_ value: String) -> String {
        value
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { part in
                guard let equals = part.firstIndex(of: "=") else { return String(part) }
                let key = String(part[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(key)=<redacted>"
            }
            .joined(separator: ";")
    }

    static func body(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.first == "{" && trimmed.last == "}",
           let data = trimmed.data(using: .utf8),
           var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for key in object.keys where isSensitive(key) { object[key] = "<redacted>" }
            if let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                return String(data: encoded, encoding: .utf8) ?? "<redacted>"
            }
        }
        return trimmed.split(separator: "&", omittingEmptySubsequences: false).map { part in
            guard let equals = part.firstIndex(of: "=") else { return String(part) }
            let key = String(part[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            let redactedValue = isSensitive(key)
                ? "<redacted>"
                : String(part[part.index(after: equals)...])
            return "\(key)=\(redactedValue)"
        }.joined(separator: "&")
    }

    static func javascript(_ value: SourceJavaScriptEvidence) -> SourceJavaScriptEvidence {
        SourceJavaScriptEvidence(
            originalScript: script(value.originalScript),
            normalizedScript: script(value.normalizedScript),
            features: value.features,
            exception: value.exception.map(script),
            succeeded: value.succeeded,
            stage: value.stage,
            exceptionType: value.exceptionType.map(script),
            stackTrace: value.stackTrace.map(script)
        )
    }

    static func log(_ value: String) -> String {
        // Logs are useful for classifying a failed bridge call, but they can
        // contain interpolated request values. Reuse the same conservative
        // redaction pass used for JS exception strings.
        script(value)
    }

    private static func script(_ value: String) -> String {
        // Keep diagnostics useful without exporting obvious credential values
        // embedded in JS literals or exception strings.
        var output = value
        let assignmentPatterns = [
            #"(?i)(cookie|token|password|passwd|secret|authorization)\s*[:=]\s*(['\"])[^'\"]*\2"#,
            #"(?i)(cookie|token|password|passwd|secret|authorization)\s*=\s*[^;&,\s]+"#
        ]
        for pattern in assignmentPatterns {
            output = output.replacingOccurrences(of: pattern, with: "$1=<redacted>", options: .regularExpression)
        }

        let callPatterns = [
            // Legado sources most often persist secrets through host calls
            // rather than object-literal assignments. Keep the key visible
            // for debugging while replacing only the value argument.
            #"(?i)(\bjava\.(?:put|putVar|setVariable)\s*\(\s*['\"](?:cookie|token|password|passwd|secret|authorization)['\"]\s*,\s*)(['\"])[^'\"]*\2"#,
            #"(?i)(\bcookie\.(?:setCookie|set)\s*\(\s*)(['\"])[^'\"]*\2"#
        ]
        for pattern in callPatterns {
            output = output.replacingOccurrences(of: pattern, with: "$1$2<redacted>$2", options: .regularExpression)
        }
        return output
    }

    private static func isSensitive(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "_", with: "-")
        return sensitiveKeys.contains(normalized)
            || normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("password")
            || normalized.contains("cookie")
    }
}

/// A portable result for a multi-source diagnostic run.  It is deliberately
/// independent from SwiftUI so it can be persisted, attached to a support
/// ticket, or generated by a command-line/CI fixture probe.
struct SourceDiagnosticBatchReport: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let keyword: String
    let reports: [SourceDiagnosticReport]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date = Date(),
        keyword: String,
        reports: [SourceDiagnosticReport]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = max(finishedAt, startedAt)
        self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reports = SourceDiagnosticReport.prioritized(reports)
    }

    var elapsedMilliseconds: Int {
        max(0, Int(finishedAt.timeIntervalSince(startedAt) * 1_000))
    }

    var totalCount: Int { reports.count }
    var passedCount: Int { reports.filter { $0.overallStatus == .passed }.count }
    var warningCount: Int { reports.filter { $0.overallStatus == .warning }.count }
    var failedCount: Int { reports.filter { [.failed, .blocked, .verificationRequired, .requiresLogin].contains($0.overallStatus) }.count }
    var firstFailure: (source: SourceDiagnosticReport, step: SourceDiagnosticStep)? {
        for report in reports {
            if let step = report.firstFailure { return (report, step) }
        }
        return nil
    }

    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    func exportText() -> String {
        var lines = [
            "Source diagnostic batch",
            "keyword: \(keyword)",
            "sources: \(totalCount)",
            "passed: \(passedCount), warnings: \(warningCount), failed: \(failedCount)",
            "elapsed: \(elapsedMilliseconds) ms"
        ]
        for report in reports {
            let status = report.overallStatus.rawValue
            let failure = report.firstFailure.map { " · firstFailure=\($0.stage.rawValue):\($0.status.rawValue)" } ?? ""
            lines.append("[\(status)] \(report.sourceName) · \(report.sourceURL)\(failure)")
            for step in report.steps {
                let count = step.matchCount > 0 ? " · results=\(step.matchCount)" : ""
                let elapsed = step.elapsedMilliseconds.map { " · \($0) ms" } ?? ""
                let code = step.responseStatusCode.map { " · HTTP \($0)" } ?? ""
                let failure = step.failureCode.map { " · failure=\($0.rawValue)" } ?? ""
                lines.append("  - \(step.stage.rawValue): \(step.status.rawValue)\(count)\(elapsed)\(code)\(failure)")
                if let request = step.requestMethod {
                    let destination = step.finalURL ?? step.requestSummary ?? ""
                    lines.append("    request: \(request) \(destination)")
                }
                if let body = step.requestBody, !body.isEmpty { lines.append("    body: \(body)") }
                if let message = step.responseSummary, !message.isEmpty { lines.append("    response: \(message)") }
                if let encodings = step.responseContentEncodings, !encodings.isEmpty {
                    let encoded = step.responseEncodedByteCount.map(String.init) ?? "?"
                    let decoded = step.responseDecodedByteCount.map(String.init) ?? "?"
                    let mode = step.responseWasDecoded ? "decoded" : "raw"
                    lines.append("    transport: \(encodings.joined(separator: ",")) · \(mode) · bytes \(encoded)→\(decoded)")
                }
                if let javascript = step.javascript, !javascript.isEmpty {
                    let featureSet = javascript.flatMap { $0.features }.uniquedPreservingOrder()
                    let failed = javascript.filter { !$0.succeeded }.count
                    let suffix = failed > 0 ? " · failed=\(failed)" : ""
                    lines.append("    javascript: \(featureSet.joined(separator: ","))\(suffix)")
                    for item in javascript where !item.succeeded {
                        if let exception = item.exception, !exception.isEmpty {
                            lines.append("      error: \(exception.prefix(240))")
                        }
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
