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

        return buildRequest(source: source, resolvedText: resolved)
    }

    private func buildRequest(source: BookSource, resolvedText: String) -> SourceRequest {
        let directive = directiveParser.parse(resolvedText)
        let url = resolveURL(directive.urlText, base: source.bookSourceUrl)

        var headers = sourceHeaders(source)
        headers.merge(directive.headers, uniquingKeysWith: { _, new in new })
        headers["User-Agent", default: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"]
        headers["Accept", default: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]

        return SourceRequest(
            url: url,
            method: directive.method,
            headers: headers,
            body: directive.body,
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
}
