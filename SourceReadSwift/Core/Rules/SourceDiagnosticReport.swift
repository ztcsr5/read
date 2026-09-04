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
    let retryCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, stage, status, requestSummary, responseSummary, matchCount,
             elapsedMilliseconds, failureClassification, requestMethod,
             requestBody, requestHeaders, responseStatusCode, responseHeaders,
             cookieSummary, finalURL, retryCount
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
        retryCount: Int = 0
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
        self.retryCount = max(0, retryCount)
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
            retryCount: try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
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
            return "\(key)=\(isSensitive(key) ? \"<redacted>\" : String(part[part.index(after: equals)...]))"
        }.joined(separator: "&")
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
                lines.append("  - \(step.stage.rawValue): \(step.status.rawValue)\(count)\(elapsed)\(code)")
                if let request = step.requestMethod { lines.append("    request: \(request) \(step.finalURL ?? step.requestSummary ?? \"\")") }
                if let body = step.requestBody, !body.isEmpty { lines.append("    body: \(body)") }
                if let message = step.responseSummary, !message.isEmpty { lines.append("    response: \(message)") }
            }
        }
        return lines.joined(separator: "\n")
    }
}
