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
        let url = URL(string: directive.urlText) ?? URL(string: source.bookSourceUrl) ?? URL(string: "https://invalid.local")!

        var headers = parseHeaders(source.header)
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
}
