import Foundation

struct SynchronousSourceLoader {
    private let requestBuilder = SourceRequestBuilder()

    func load(urlText: String, source: BookSource, timeout: TimeInterval = 20) -> String {
        loadResponse(urlText: urlText, source: source, timeout: timeout)?.body ?? ""
    }

    func loadResponse(urlText: String, source: BookSource, timeout: TimeInterval = 20, cookieHeader: String? = nil) -> SourceResponse? {
        let request = requestBuilder.buildPageRequest(source: source, urlText: urlText)
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let cookieHeader, !cookieHeader.isEmpty, urlRequest.value(forHTTPHeaderField: "Cookie") == nil {
            urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SynchronousLoadResultBox()

        URLSession.shared.dataTask(with: urlRequest) { data, response, _ in
            var headers: [String: String] = [:]
            var finalURL: URL?
            var statusCode = 200
            if let http = response as? HTTPURLResponse {
                finalURL = http.url
                statusCode = http.statusCode
                headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                    result[String(describing: item.key)] = String(describing: item.value)
                }
            }
            resultBox.store(data: data, headers: headers, url: finalURL, statusCode: statusCode)
            semaphore.signal()
        }.resume()

        let deadline = DispatchTime.now() + timeout
        guard semaphore.wait(timeout: deadline) == .success,
              let result = resultBox.load() else {
            return nil
        }
        let responseURL = result.url ?? request.url
        // JS callbacks use this synchronous loader. Mirror URLSessionSourceNetworkClient
        // by persisting response cookies so subsequent source requests (including
        // java.ajax chains) see the same session state.
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: result.headers, for: responseURL)
        for cookie in responseCookies { HTTPCookieStorage.shared.setCookie(cookie) }
        let body = ResponseTextDecoder().decode(data: result.data, headers: result.headers, preferredCharset: request.expectedCharset)
        return SourceResponse(url: responseURL, statusCode: result.statusCode, headers: result.headers, body: body, data: result.data)
    }
}

private final class SynchronousLoadResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (data: Data, headers: [String: String], url: URL?, statusCode: Int)?

    func store(data: Data?, headers: [String: String], url: URL?, statusCode: Int) {
        guard let data else {
            lock.lock()
            result = nil
            lock.unlock()
            return
        }
        lock.lock()
        result = (data, headers, url, statusCode)
        lock.unlock()
    }

    func load() -> (data: Data, headers: [String: String], url: URL?, statusCode: Int)? {
        lock.lock()
        let current = result
        lock.unlock()
        return current
    }
}
