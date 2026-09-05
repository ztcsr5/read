import Foundation

/// JavaScript execution evidence captured by the Legado compatibility layer.
/// Scripts are retained for local debugging and redacted before export.
struct SourceJavaScriptEvidence: Codable, Hashable, Sendable {
    let originalScript: String
    let normalizedScript: String
    let features: [String]
    let exception: String?
    /// Stage is optional for reports created by older builds.  New runtime
    /// records use the same value as the enclosing pipeline stage.
    let stage: String?
    /// JavaScriptCore exposes the error name and stack separately from the
    /// user-facing message. Keeping both makes source repair actionable while
    /// allowing the exporter to redact secrets in each field.
    let exceptionType: String?
    let stackTrace: String?
    let succeeded: Bool

    private enum CodingKeys: String, CodingKey {
        case originalScript, normalizedScript, features, exception, stage,
             exceptionType, stackTrace, succeeded
    }

    init(
        originalScript: String,
        normalizedScript: String,
        features: [String],
        exception: String? = nil,
        succeeded: Bool,
        stage: String? = nil,
        exceptionType: String? = nil,
        stackTrace: String? = nil
    ) {
        self.originalScript = originalScript
        self.normalizedScript = normalizedScript
        self.features = features
        self.exception = exception
        self.stage = stage
        self.exceptionType = exceptionType
        self.stackTrace = stackTrace
        self.succeeded = succeeded
    }

    /// Keep reports produced before stage/type/stack diagnostics were added
    /// readable.  `decodeIfPresent` is intentional here: old reports contain
    /// the same JavaScript object but do not have the three new keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            originalScript: try container.decode(String.self, forKey: .originalScript),
            normalizedScript: try container.decode(String.self, forKey: .normalizedScript),
            features: try container.decodeIfPresent([String].self, forKey: .features) ?? [],
            exception: try container.decodeIfPresent(String.self, forKey: .exception),
            succeeded: try container.decodeIfPresent(Bool.self, forKey: .succeeded) ?? false,
            stage: try container.decodeIfPresent(String.self, forKey: .stage),
            exceptionType: try container.decodeIfPresent(String.self, forKey: .exceptionType),
            stackTrace: try container.decodeIfPresent(String.self, forKey: .stackTrace)
        )
    }
}

/// Raw request/response evidence captured by the source engine.  Values are
/// redacted when converted into `SourceDiagnosticStep`, never at the network
/// boundary, so parser behavior remains unaffected while exported reports are
/// safe to share.
struct SourceDiagnosticEvidence: Sendable {
    let requestMethod: String
    let requestBody: String?
    let requestHeaders: [String: String]
    let responseStatusCode: Int
    let responseHeaders: [String: String]
    let cookieSummary: String?
    let finalURL: String
    let responseEncodedByteCount: Int?
    let responseDecodedByteCount: Int
    let responseContentEncodings: [String]
    let responseWasDecoded: Bool
    let javascript: [SourceJavaScriptEvidence]
    let executionLogs: [String]

    init(
        request: SourceRequest,
        response: SourceResponse,
        javascript: [SourceJavaScriptEvidence] = [],
        executionLogs: [String] = []
    ) {
        self.requestMethod = request.method.rawValue
        self.requestBody = request.body.flatMap { String(data: $0, encoding: .utf8) }
        self.requestHeaders = request.headers
        self.responseStatusCode = response.statusCode
        self.responseHeaders = response.headers
        self.cookieSummary = request.headers.first { key, _ in
            key.caseInsensitiveCompare("Cookie") == .orderedSame
        }?.value ?? response.headers.first { key, _ in
            key.caseInsensitiveCompare("Set-Cookie") == .orderedSame
        }?.value
        self.finalURL = response.url.absoluteString
        self.responseEncodedByteCount = response.encodedByteCount
        self.responseDecodedByteCount = response.data.count
        self.responseContentEncodings = response.contentEncodings
        self.responseWasDecoded = response.bodyWasDecoded
        self.javascript = javascript
        self.executionLogs = executionLogs
    }

    func with(
        javascript: [SourceJavaScriptEvidence],
        executionLogs: [String]? = nil
    ) -> SourceDiagnosticEvidence {
        SourceDiagnosticEvidence(
            requestMethod: requestMethod,
            requestBody: requestBody,
            requestHeaders: requestHeaders,
            responseStatusCode: responseStatusCode,
            responseHeaders: responseHeaders,
            cookieSummary: cookieSummary,
            finalURL: finalURL,
            responseEncodedByteCount: responseEncodedByteCount,
            responseDecodedByteCount: responseDecodedByteCount,
            responseContentEncodings: responseContentEncodings,
            responseWasDecoded: responseWasDecoded,
            javascript: javascript,
            executionLogs: executionLogs ?? self.executionLogs
        )
    }

    private init(
        requestMethod: String,
        requestBody: String?,
        requestHeaders: [String: String],
        responseStatusCode: Int,
        responseHeaders: [String: String],
        cookieSummary: String?,
        finalURL: String,
        responseEncodedByteCount: Int?,
        responseDecodedByteCount: Int,
        responseContentEncodings: [String],
        responseWasDecoded: Bool,
        javascript: [SourceJavaScriptEvidence],
        executionLogs: [String]
    ) {
        self.requestMethod = requestMethod
        self.requestBody = requestBody
        self.requestHeaders = requestHeaders
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.cookieSummary = cookieSummary
        self.finalURL = finalURL
        self.responseEncodedByteCount = responseEncodedByteCount
        self.responseDecodedByteCount = responseDecodedByteCount
        self.responseContentEncodings = responseContentEncodings
        self.responseWasDecoded = responseWasDecoded
        self.javascript = javascript
        self.executionLogs = executionLogs
    }
}

/// Optional capability implemented by engines that can expose structured
/// request evidence.  Test doubles and third-party engines may omit it; the
/// pipeline remains fully compatible and simply keeps its existing summaries.
protocol SourceDiagnosticEvidenceProvider: Sendable {
    func resetDiagnosticEvidence(sourceURL: String)
    func diagnosticEvidence(sourceURL: String, stage: SourceDiagnosticStage) -> SourceDiagnosticEvidence?
}
