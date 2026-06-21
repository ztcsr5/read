import Foundation

enum SourceHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
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
                return .failure(.network("\u{54cd}\u{5e94}\u{4e0d}\u{662f} HTTPURLResponse"))
            }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
            }
            let text = ResponseTextDecoder().decode(data: data, headers: headers, preferredCharset: request.expectedCharset)
            let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: http.url ?? request.url)
            if !responseCookies.isEmpty {
                await cookieStore.store(responseCookies, for: http.url ?? request.url)
            }
            if (400...599).contains(http.statusCode) {
                return .failure(.network("HTTP \(http.statusCode)"))
            }
            return .success(SourceResponse(
                url: http.url ?? request.url,
                statusCode: http.statusCode,
                headers: headers,
                body: text,
                data: data
            ))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
