import Foundation

struct SearchURLResolver {
    private let ruleResolver = LegadoRuleResolver()

    func resolve(source: BookSource, keyword: String, page: Int) -> Result<String, SourceEngineError> {
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else {
            return .failure(.invalidSource("searchUrl \u{4e3a}\u{7a7a}"))
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
            return evaluateScript(script, source: source, variables: [
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
            return evaluateScript(script, source: source, variables: [
                "keyword": keyword,
                "key": keyword,
                "page": page,
                "baseUrl": source.bookSourceUrl
            ])
        }

        return .success(interpolated)
    }

    private func evaluateScript(
        _ script: String,
        source: BookSource,
        variables: [String: Any]
    ) -> Result<String, SourceEngineError> {
        let direct = makeRuntime(source: source).evaluate(script, variables: variables)
        if case .failure(.javascript) = direct, script.contains("return") {
            return makeRuntime(source: source).evaluate("(function(){\(script)})()", variables: variables)
        }
        return direct
    }

    private func makeRuntime(source: BookSource) -> JSCoreRuntime {
        JSCoreRuntime { urlText in
            SynchronousSourceLoader().load(urlText: urlText, source: source)
        }
    }
}
