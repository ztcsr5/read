import Foundation

struct SourceRequestBuilder {
    private let directiveParser = SourceURLDirectiveParser()

    func buildPageRequest(source: BookSource, urlText: String) -> SourceRequest {
        buildRequest(source: source, resolvedText: urlText)
    }

    func buildSearchRequest(source: BookSource, searchUrl: String, keyword: String, page: Int) -> SourceRequest {
        let resolved = searchUrl
            .replacingOccurrences(of: "{{key}}", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
            .replacingOccurrences(of: "{{keyword}}", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
            .replacingOccurrences(of: "{{page}}", with: String(page))

        return buildRequest(source: source, resolvedText: resolved, keyword: keyword, page: page)
    }

    private func buildRequest(source: BookSource, resolvedText: String, keyword: String? = nil, page: Int? = nil) -> SourceRequest {
        let directive = directiveParser.parse(resolvedText)
        let url = resolveURL(directive.urlText, base: source.bookSourceUrl)
        let sourceOptions = requestOptions(source, keyword: keyword, page: page)
        let charset = sourceCharset(source)

        var headers = sourceHeaders(source)
        headers.merge(sourceOptions.headers, uniquingKeysWith: { _, new in new })
        headers.merge(directive.headers, uniquingKeysWith: { _, new in new })
        headers["User-Agent", default: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"]
        headers["Accept", default: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]

        let body = directive.body ?? sourceOptions.body
        let method: SourceHTTPMethod = {
            if directive.method == .post { return .post }
            if sourceOptions.method == .post { return .post }
            if body != nil { return .post }
            return .get
        }()

        return SourceRequest(
            url: url,
            method: method,
            headers: headers,
            body: body,
            expectedCharset: charset,
            timeout: 20
        )
    }

    private func parseHeaders(_ text: String?) -> [String: String] {
        guard let text, !text.isEmpty else { return [:] }
        if let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object.reduce(into: [:]) { result, item in
                result[item.key] = String(describing: item.value)
            }
        }
        return [:]
    }

    private func stringMap(_ object: [String: Any]) -> [String: String] {
        object.reduce(into: [:]) { result, item in
            result[item.key] = String(describing: item.value)
        }
    }

    private func resolveURL(_ text: String, base: String) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        if let baseURL = URL(string: base),
           let relative = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
            return relative
        }
        return URL(string: base) ?? URL(string: "https://invalid.local")!
    }

    private func sourceHeaders(_ source: BookSource) -> [String: String] {
        var headers = parseHeaders(source.header)
        for key in ["headers", "bookSourceHeader"] {
            headers.merge(parseHeaders(source.raw[key]), uniquingKeysWith: { _, new in new })
        }
        if let customConfig = source.customConfig,
           let data = customConfig.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let nested = object["headers"] as? [String: Any] {
                headers.merge(stringMap(nested), uniquingKeysWith: { _, new in new })
            }
            if let nested = object["header"] as? [String: Any] {
                headers.merge(stringMap(nested), uniquingKeysWith: { _, new in new })
            }
            if let text = object["header"] as? String {
                headers.merge(parseHeaders(text), uniquingKeysWith: { _, new in new })
            }
            if let cookie = object["cookie"] as? String, !cookie.isEmpty {
                headers["Cookie"] = cookie
            }
        }
        if let cookie = source.raw["cookie"], !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        return headers
    }

    private func requestOptions(_ source: BookSource, keyword: String?, page: Int?) -> (method: SourceHTTPMethod?, body: Data?, headers: [String: String]) {
        var method: SourceHTTPMethod?
        var body: Data?
        var headers: [String: String] = [:]

        func apply(_ object: [String: Any]) {
            if let methodText = object["method"] as? String, methodText.uppercased() == "POST" {
                method = .post
            }
            if let methodText = object["httpMethod"] as? String, methodText.uppercased() == "POST" {
                method = .post
            }
            if let bodyText = object["body"] as? String {
                body = Data(interpolate(bodyText, keyword: keyword, page: page).utf8)
                method = .post
            }
            if let bodyText = object["requestBody"] as? String {
                body = Data(interpolate(bodyText, keyword: keyword, page: page).utf8)
                method = .post
            }
            if let bodyText = object["postBody"] as? String {
                body = Data(interpolate(bodyText, keyword: keyword, page: page).utf8)
                method = .post
            }
            if let nested = object["headers"] as? [String: Any] {
                headers.merge(stringMap(nested), uniquingKeysWith: { _, new in new })
            }
            if let nested = object["header"] as? [String: Any] {
                headers.merge(stringMap(nested), uniquingKeysWith: { _, new in new })
            }
            if let text = object["headers"] as? String {
                headers.merge(parseHeaders(text), uniquingKeysWith: { _, new in new })
            }
            if let text = object["header"] as? String {
                headers.merge(parseHeaders(text), uniquingKeysWith: { _, new in new })
            }
        }

        if let customConfig = source.customConfig,
           let data = customConfig.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            apply(object)
        }

        apply(source.raw.reduce(into: [String: Any]()) { result, item in
            result[item.key] = item.value
        })
        return (method, body, headers)
    }

    private func sourceCharset(_ source: BookSource) -> String? {
        if let charset = source.raw["charset"]?.trimmingCharacters(in: .whitespacesAndNewlines), !charset.isEmpty {
            return charset
        }
        if let customConfig = source.customConfig,
           let data = customConfig.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["charset", "encoding", "encode"] {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }

    private func interpolate(_ text: String, keyword: String?, page: Int?) -> String {
        var output = text
        if let keyword {
            let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            output = output
                .replacingOccurrences(of: "{{key}}", with: encoded)
                .replacingOccurrences(of: "{{keyword}}", with: encoded)
        }
        if let page {
            output = output.replacingOccurrences(of: "{{page}}", with: String(page))
        }
        return output
    }
}
