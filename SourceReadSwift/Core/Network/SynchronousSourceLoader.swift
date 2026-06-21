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
        var loadedData: Data?
        var loadedHeaders: [String: String] = [:]

        URLSession.shared.dataTask(with: urlRequest) { data, response, _ in
            loadedData = data
            if let http = response as? HTTPURLResponse {
                loadedHeaders = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                    result[String(describing: item.key)] = String(describing: item.value)
                }
            }
            semaphore.signal()
        }.resume()

        let deadline = DispatchTime.now() + timeout
        guard semaphore.wait(timeout: deadline) == .success, let data = loadedData else {
            return ""
        }
        return ResponseTextDecoder().decode(data: data, headers: loadedHeaders)
    }
}

