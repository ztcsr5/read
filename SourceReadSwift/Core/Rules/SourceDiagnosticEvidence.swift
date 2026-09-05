import Foundation

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

    init(
        request: SourceRequest,
        response: SourceResponse
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
    }
}

/// Optional capability implemented by engines that can expose structured
/// request evidence.  Test doubles and third-party engines may omit it; the
/// pipeline remains fully compatible and simply keeps its existing summaries.
protocol SourceDiagnosticEvidenceProvider: Sendable {
    func resetDiagnosticEvidence(sourceURL: String)
    func diagnosticEvidence(sourceURL: String, stage: SourceDiagnosticStage) -> SourceDiagnosticEvidence?
}
