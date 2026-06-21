import Foundation

struct SynchronousSourceLoader {
    private let requestBuilder = SourceRequestBuilder()

    func load(urlText: String, source: BookSource, timeout: TimeInterval = 20) -> String {
        let request = requestBuilder.buildPageRequest(source: source, urlText: urlText)
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SynchronousLoadResultBox()

        URLSession.shared.dataTask(with: urlRequest) { data, response, _ in
            var headers: [String: String] = [:]
            if let http = response as? HTTPURLResponse {
                headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                    result[String(describing: item.key)] = String(describing: item.value)
                }
            }
            resultBox.store(data: data, headers: headers)
            semaphore.signal()
        }.resume()

        let deadline = DispatchTime.now() + timeout
        guard semaphore.wait(timeout: deadline) == .success,
              let result = resultBox.load() else {
            return ""
        }
        return ResponseTextDecoder().decode(data: result.data, headers: result.headers, preferredCharset: request.expectedCharset)
    }
}

private final class SynchronousLoadResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (data: Data, headers: [String: String])?

    func store(data: Data?, headers: [String: String]) {
        guard let data else { return }
        lock.lock()
        result = (data, headers)
        lock.unlock()
    }

    func load() -> (data: Data, headers: [String: String])? {
        lock.lock()
        let current = result
        lock.unlock()
        return current
    }
}
