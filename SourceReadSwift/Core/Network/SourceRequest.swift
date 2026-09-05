import Foundation

enum SourceHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case head = "HEAD"
}

struct SourceRequest: Sendable {
    let url: URL
    let method: SourceHTTPMethod
    let headers: [String: String]
    let body: Data?
    let expectedCharset: String?
    let timeout: TimeInterval
}

struct SourceResponse: Sendable {
    let url: URL
    let statusCode: Int
    let headers: [String: String]
    let body: String
    let data: Data
    /// Byte count before transport decoding when the adapter supplied a
    /// compressed payload.  Plain text-only fixtures leave this nil.
    let encodedByteCount: Int?
    /// True when `data`/`body` were produced by decoding Content-Encoding.
    let bodyWasDecoded: Bool
    /// Normalized Content-Encoding tokens observed on the response.
    let contentEncodings: [String]

    init(
        url: URL,
        statusCode: Int,
        headers: [String: String],
        body: String,
        data: Data,
        encodedByteCount: Int? = nil,
        bodyWasDecoded: Bool = false,
        contentEncodings: [String] = []
    ) {
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.data = data
        self.encodedByteCount = encodedByteCount
        self.bodyWasDecoded = bodyWasDecoded
        self.contentEncodings = contentEncodings
    }
}

protocol SourceNetworkClient: Sendable {
    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError>
}

final class URLSessionSourceNetworkClient: SourceNetworkClient, @unchecked Sendable {
    private let session: URLSession
    private let cookieStore: SourceCookieStore

    init(session: URLSession = .shared, cookieStore: SourceCookieStore = SourceCookieStore()) {
        self.session = session
        self.cookieStore = cookieStore
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if request.headers["Cookie"] == nil, let cookieHeader = await cookieStore.cookieHeader(for: request.url) {
            urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("响应不是 HTTPURLResponse"))
            }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
            }
            let decoded = ResponseBodyDecoder().decodeResult(data: data, headers: headers)
            let decodedData = decoded.data
            let text = ResponseTextDecoder().decode(data: decodedData, headers: headers, preferredCharset: request.expectedCharset)
            // Foundation does not reliably parse a combined Set-Cookie field
            // when Expires contains a comma. Parse each cookie value first,
            // then persist the complete response set for the next stage.
            await cookieStore.storeSetCookieHeaders(headers, for: http.url ?? request.url)
            if (400...599).contains(http.statusCode) {
                return .failure(.network("HTTP \(http.statusCode)"))
            }
            return .success(SourceResponse(
                url: http.url ?? request.url,
                statusCode: http.statusCode,
                headers: headers,
                body: text,
                data: decodedData,
                encodedByteCount: decoded.wasDecoded ? data.count : nil,
                bodyWasDecoded: decoded.wasDecoded,
                contentEncodings: decoded.encodings
            ))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
