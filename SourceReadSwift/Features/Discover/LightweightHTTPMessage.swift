import Foundation

/// A byte-oriented HTTP/1.1 request parser for the LAN source editor.  Header
/// framing is deliberately performed on Data rather than String so a UTF-8
/// body cannot shift the Content-Length offset on Windows/PC browsers.
struct LightweightHTTPRequest {
    let method: String
    let target: String
    let path: String
    let headers: [String: String]
    let body: Data

    var query: String? {
        guard let separator = target.firstIndex(of: "?") else { return nil }
        return String(target[target.index(after: separator)...])
    }
}

enum LightweightHTTPParseResult {
    case incomplete
    case complete(LightweightHTTPRequest)
    case failure(statusCode: Int, message: String)
}

enum LightweightHTTPParser {
    static let maximumHeaderBytes = 64 * 1024
    static let maximumBodyBytes = 2 * 1024 * 1024
    private static let headerDelimiter = Data([13, 10, 13, 10])

    static func parse(_ data: Data) -> LightweightHTTPParseResult {
        guard let delimiterRange = data.range(of: headerDelimiter) else {
            if data.count > maximumHeaderBytes {
                return .failure(statusCode: 431, message: "Request headers too large")
            }
            return .incomplete
        }

        guard delimiterRange.lowerBound <= maximumHeaderBytes else {
            return .failure(statusCode: 431, message: "Request headers too large")
        }

        let headerEnd = delimiterRange.upperBound
        guard let headerText = String(data: data[..<delimiterRange.lowerBound], encoding: .utf8) else {
            return .failure(statusCode: 400, message: "Invalid UTF-8 request headers")
        }
        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first, !requestLine.isEmpty else {
            return .failure(statusCode: 400, message: "Empty request")
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            return .failure(statusCode: 400, message: "Invalid request line")
        }

        let method = requestParts[0].uppercased()
        let target = String(requestParts[1])
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            headers[key] = String(value)
        }

        if let transferEncoding = headers["transfer-encoding"],
           transferEncoding.localizedCaseInsensitiveContains("chunked") {
            return .failure(statusCode: 501, message: "Chunked requests are not supported")
        }

        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0 else {
                return .failure(statusCode: 400, message: "Invalid Content-Length")
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard contentLength <= maximumBodyBytes else {
            return .failure(statusCode: 413, message: "Request body too large")
        }

        let requiredBytes = headerEnd + contentLength
        guard data.count >= requiredBytes else { return .incomplete }
        let body = Data(data[headerEnd..<requiredBytes])
        return .complete(LightweightHTTPRequest(method: method, target: target, path: path, headers: headers, body: body))
    }
}
