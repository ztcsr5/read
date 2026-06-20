import Foundation

protocol SourceEngine: Sendable {
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError>
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError>
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError>
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError>
}

final class LegadoSourceEngine: SourceEngine {
    private let network: SourceNetworkClient
    private let diagnostics: DiagnosticSink
    private let requestBuilder = SourceRequestBuilder()
    private let searchURLResolver = SearchURLResolver()

    init(
        network: SourceNetworkClient = URLSessionSourceNetworkClient(),
        diagnostics: DiagnosticSink = .noop
    ) {
        self.network = network
        self.diagnostics = diagnostics
    }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        await diagnostics.emit(.init(
            level: .info,
            stage: "search.prepare",
            sourceName: source.bookSourceName,
            message: "\u{51c6}\u{5907}\u{641c}\u{7d22}",
            details: ["keyword": keyword, "page": String(page)]
        ))

        let searchUrl: String
        switch searchURLResolver.resolve(source: source, keyword: keyword, page: page) {
        case .success(let value):
            searchUrl = value
        case .failure(let error):
            return .failure(error)
        }

        let request = requestBuilder.buildSearchRequest(source: source, searchUrl: searchUrl, keyword: keyword, page: page)
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "search.load") {
        case .success(let response):
            guard !response.body.isEmpty else {
                return .failure(.empty("\u{641c}\u{7d22}\u{54cd}\u{5e94}\u{4e3a}\u{7a7a}"))
            }
            return SearchResultParser().parse(source: source, response: response)
        case .failure(let error):
            return .failure(error)
        }
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        let request = requestBuilder.buildPageRequest(source: source, urlText: book.bookUrl)
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "detail.load") {
        case .success(let response):
            return BookDetailParser().parse(source: source, book: book, response: response)
        case .failure(let error):
            return .failure(error)
        }
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        let request = requestBuilder.buildPageRequest(source: source, urlText: book.bookUrl)
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "toc.load") {
        case .success(let response):
            return ChapterListParser().parse(source: source, book: book, response: response)
        case .failure(let error):
            return .failure(error)
        }
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        let request = requestBuilder.buildPageRequest(source: source, urlText: chapter.url)
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "content.load") {
        case .success(let response):
            return ContentParser().parse(source: source, chapter: chapter, response: response)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func loadWithOptionalWebViewFallback(
        _ request: SourceRequest,
        source: BookSource,
        stage: String
    ) async -> Result<SourceResponse, SourceEngineError> {
        let primary = await network.load(request)
        if case .success(let response) = primary, !shouldUseWebViewFallback(source: source, response: response) {
            return .success(response)
        }
        guard shouldUseWebView(source: source) else {
            return primary
        }

        await diagnostics.emit(.init(
            level: .info,
            stage: "\(stage).webview",
            sourceName: source.bookSourceName,
            message: "\u{5207}\u{6362} WebView fallback",
            details: ["url": request.url.absoluteString]
        ))

        let delay = webViewDelay(source: source)
        let htmlResult = await WebViewFallback().load(url: request.url, delay: delay)
        switch htmlResult {
        case .success(let html):
            return .success(SourceResponse(
                url: request.url,
                statusCode: 200,
                headers: [:],
                body: html,
                data: Data(html.utf8)
            ))
        case .failure(let error):
            return .failure(error)
        }
    }

    private func shouldUseWebView(source: BookSource) -> Bool {
        if source.raw["webView"]?.lowercased() == "true" { return true }
        if source.raw["bookSourceType"]?.lowercased().contains("web") == true { return true }
        return false
    }

    private func shouldUseWebViewFallback(source: BookSource, response: SourceResponse) -> Bool {
        guard shouldUseWebView(source: source) else { return false }
        let text = response.body.lowercased()
        if text.isEmpty { return true }
        return text.contains("cloudflare")
            || text.contains("cf-challenge")
            || text.contains("captcha")
            || text.contains("\u{5b89}\u{5168}\u{9a8c}\u{8bc1}")
            || text.contains("\u{767e}\u{5ea6}\u{5b89}\u{5168}\u{9a8c}\u{8bc1}")
            || text.contains("\u{4eba}\u{673a}\u{9a8c}\u{8bc1}")
    }

    private func webViewDelay(source: BookSource) -> TimeInterval {
        if let raw = source.raw["webViewDelayTime"], let value = Double(raw) {
            return max(0.5, min(value / 1000, 20))
        }
        return 3
    }
}
