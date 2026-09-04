import Foundation

struct SynchronousSourceLoader {
    private let requestBuilder = SourceRequestBuilder()

    func load(
        urlText: String,
        source: BookSource,
        timeout: TimeInterval? = nil,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil
    ) -> String {
        loadResponse(
            urlText: urlText,
            source: source,
            timeout: timeout,
            cookieHeader: cookieHeader,
            persistentValues: persistentValues,
            persistentState: persistentState
        )?.body ?? ""
    }

    func loadResponse(
        urlText: String,
        source: BookSource,
        timeout: TimeInterval? = nil,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:],
        persistentState: RulePersistentState? = nil
    ) -> SourceResponse? {
        // Keep the explicit callback cookie in lockstep with the persistent
        // state snapshot.  This matters for JS stages that receive a cookie
        // from a response and immediately call java.ajax/fetch again.
        var effectivePersistentValues = persistentValues
        if let cookieHeader, !cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            effectivePersistentValues["cookieHeader"] = cookieHeader
        }
        let request = requestBuilder.buildPageRequest(
            source: source,
            urlText: urlText,
            persistentValues: effectivePersistentValues
        )
        let effectiveTimeout = timeout ?? request.timeout
        var urlRequest = URLRequest(url: request.url, timeoutInterval: effectiveTimeout)
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

        let deadline = DispatchTime.now() + effectiveTimeout
        guard semaphore.wait(timeout: deadline) == .success,
              let result = resultBox.load() else {
            return nil
        }
        let responseURL = result.url ?? request.url
        // JS callbacks use this synchronous loader. Mirror URLSessionSourceNetworkClient
        // by persisting response cookies so subsequent source requests (including
        // java.ajax chains) see the same session state.
        let responseCookies = CookieHeaderParser.setCookieValues(from: result.headers).flatMap { value in
            HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: responseURL)
        }
        for cookie in responseCookies { HTTPCookieStorage.shared.setCookie(cookie) }
        // Keep the JS-visible state and Foundation's cookie jar in sync.  A
        // source may receive `sid=...` in one ajax call and interpolate the
        // merged Cookie header into the very next request.
        if let persistentState {
            let previous = effectivePersistentValues["cookieHeader"]
                ?? cookieHeader
                ?? HTTPCookieStorage.shared.cookies(for: responseURL).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            let setCookie = CookieHeaderParser.setCookieValues(from: result.headers)
                .compactMap { CookieHeaderParser.cookiePair(fromSetCookie: $0) }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            let merged = CookieHeaderParser.merge(setCookie, into: previous)
            if !merged.isEmpty { persistentState.put(merged, for: "cookieHeader") }
        }
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
