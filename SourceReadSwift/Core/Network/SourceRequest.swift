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

    init(session: URLSession = .shared) {
        self.session = session
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("响应不是 HTTPURLResponse"))
            }
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
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
