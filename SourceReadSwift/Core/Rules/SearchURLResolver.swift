import Foundation

struct SearchURLResolver {
    private let ruleResolver = LegadoRuleResolver()

    func resolve(source: BookSource, keyword: String, page: Int) -> Result<String, SourceEngineError> {
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else {
            return .failure(.invalidSource("searchUrl 为空"))
        }

        let interpolated = ruleResolver.interpolate(
            searchUrl,
            keyword: keyword,
            page: page,
            baseUrl: source.bookSourceUrl
        )

        let trimmed = interpolated.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@js:") {
            let script = String(trimmed.dropFirst(4))
            return JSCoreRuntime().evaluate(script, variables: [
                "keyword": keyword,
                "key": keyword,
                "page": page,
                "baseUrl": source.bookSourceUrl
            ])
        }

        if trimmed.hasPrefix("<js>"), trimmed.hasSuffix("</js>") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -5)
            let script = String(trimmed[start..<end])
            return JSCoreRuntime().evaluate(script, variables: [
                "keyword": keyword,
                "key": keyword,
                "page": page,
                "baseUrl": source.bookSourceUrl
            ])
        }

        return .success(interpolated)
    }
}

