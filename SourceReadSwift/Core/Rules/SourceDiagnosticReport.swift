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

    init(
        id: UUID = UUID(),
        stage: SourceDiagnosticStage,
        status: SourceHealthStatus,
        requestSummary: String? = nil,
        responseSummary: String? = nil,
        matchCount: Int = 0,
        elapsedMilliseconds: Int? = nil,
        failureClassification: String? = nil
    ) {
        self.id = id
        self.stage = stage
        self.status = status
        self.requestSummary = requestSummary
        self.responseSummary = responseSummary
        self.matchCount = max(matchCount, 0)
        self.elapsedMilliseconds = elapsedMilliseconds
        self.failureClassification = failureClassification
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
