import Foundation

protocol SourceEngine: Sendable {
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError>
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError>
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError>
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError>
}

final class LegadoSourceEngine: SourceEngine, @unchecked Sendable {
    private let network: SourceNetworkClient
    private let diagnostics: DiagnosticSink
    private let cookieStore: SourceCookieStore
    private let purifyRules: () async -> [String]
    private let requestBuilder = SourceRequestBuilder()
    private let searchURLResolver = SearchURLResolver()

    init(
        network: SourceNetworkClient? = nil,
        cookieStore: SourceCookieStore = SourceCookieStore(),
        diagnostics: DiagnosticSink = .noop,
        purifyRules: @escaping () async -> [String] = { [] }
    ) {
        self.cookieStore = cookieStore
        self.network = network ?? URLSessionSourceNetworkClient(cookieStore: cookieStore)
        self.diagnostics = diagnostics
        self.purifyRules = purifyRules
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
            await emitFailure(error, stage: "search.url", source: source)
            return .failure(error)
        }

        let request = requestBuilder.buildSearchRequest(source: source, searchUrl: searchUrl, keyword: keyword, page: page)
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "search.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source)
            guard !transformedResponse.body.isEmpty else {
                let error = SourceEngineError.empty("\u{641c}\u{7d22}\u{54cd}\u{5e94}\u{4e3a}\u{7a7a}")
                await emitFailure(error, stage: "search.empty", source: source, details: ["url": transformedResponse.url.absoluteString])
                return .failure(error)
            }
            let parsed = SearchResultParser().parse(source: source, response: transformedResponse)
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "search.parse", source: source, details: ["url": transformedResponse.url.absoluteString])
            }
            return parsed
        case .failure(let error):
            await emitFailure(error, stage: "search.load", source: source, details: ["url": request.url.absoluteString])
            return .failure(error)
        }
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        let request = requestBuilder.buildPageRequest(source: source, urlText: book.bookUrl)
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "detail.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source)
            let parsed = BookDetailParser().parse(source: source, book: book, response: transformedResponse)
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "detail.parse", source: source, details: ["url": transformedResponse.url.absoluteString])
            }
            return parsed
        case .failure(let error):
            await emitFailure(error, stage: "detail.load", source: source, details: ["url": request.url.absoluteString])
            return .failure(error)
        }
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        let tocURL = book.tocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? book.bookUrl
        let request = requestBuilder.buildPageRequest(source: source, urlText: tocURL)
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "toc.load") {
        case .success(let response):
            let parsed = parseChapterListPage(source: source, book: book, response: response)
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "toc.parse", source: source, details: ["url": response.url.absoluteString])
            }
            guard case .success(let firstPage) = parsed else {
                return parsed.map { $0.chapters }
            }
            return await appendNextChapterListPages(
                firstPage,
                source: source,
                book: book,
                firstURL: response.url
            )
        case .failure(let error):
            await emitFailure(error, stage: "toc.load", source: source, details: ["url": request.url.absoluteString])
            return .failure(error)
        }
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        let request = requestBuilder.buildPageRequest(source: source, urlText: chapter.url)
        let globalPurifyRules = await purifyRules()
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "content.load") {
        case .success(let response):
            let parsed = parseContentPage(
                source: source,
                chapter: chapter,
                response: response,
                globalPurifyRules: globalPurifyRules
            )
            if case .failure(let error) = parsed {
                await emitFailure(error, stage: "content.parse", source: source, details: ["url": response.url.absoluteString])
            }
            guard case .success(let firstPage) = parsed else { return parsed }
            return await appendNextContentPages(
                firstPage,
                source: source,
                chapter: chapter,
                firstURL: response.url,
                globalPurifyRules: globalPurifyRules
            )
        case .failure(let error):
            await emitFailure(error, stage: "content.load", source: source, details: ["url": request.url.absoluteString])
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
        let htmlResult = await WebViewFallback(cookieStore: cookieStore).load(url: request.url, delay: delay)
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

    private func transformBodyIfNeeded(_ response: SourceResponse, source: BookSource) -> SourceResponse {
        guard let script = bodyJSScript(source), !script.isEmpty else { return response }
        let runtime = JSCoreRuntime { urlText in
            SynchronousSourceLoader().load(urlText: urlText, source: source)
        }
        let variables: [String: Any] = [
            "result": response.body,
            "html": response.body,
            "body": response.body,
            "baseUrl": response.url.absoluteString,
            "source": source
        ]

        let evaluated = runtime.evaluate(script, variables: variables)
        let result: Result<String, SourceEngineError>
        if case .failure(.javascript) = evaluated, script.contains("return") {
            result = runtime.evaluate("(function(){\(script)})()", variables: variables)
        } else {
            result = evaluated
        }

        guard case .success(let output) = result else { return response }
        let transformed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transformed.isEmpty else { return response }
        return SourceResponse(
            url: response.url,
            statusCode: response.statusCode,
            headers: response.headers,
            body: output,
            data: Data(output.utf8)
        )
    }

    private func parseContentPage(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String]
    ) -> Result<ChapterContent, SourceEngineError> {
        let transformedResponse = transformBodyIfNeeded(response, source: source)
        return ContentParser().parse(
            source: source,
            chapter: chapter,
            response: transformedResponse,
            globalPurifyRules: globalPurifyRules
        )
    }

    private func parseChapterListPage(
        source: BookSource,
        book: BookDetail,
        response: SourceResponse
    ) -> Result<ChapterListPage, SourceEngineError> {
        let transformedResponse = transformBodyIfNeeded(response, source: source)
        return ChapterListParser().parsePage(source: source, book: book, response: transformedResponse)
    }

    private func appendNextChapterListPages(
        _ firstPage: ChapterListPage,
        source: BookSource,
        book: BookDetail,
        firstURL: URL
    ) async -> Result<[BookChapter], SourceEngineError> {
        var chapters = firstPage.chapters
        var nextURLText = firstPage.nextTocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var seenURLs: Set<String> = [firstURL.absoluteString]
        var pagesLoaded = 1
        let maxPages = 30

        while let currentNext = nextURLText, pagesLoaded < maxPages {
            let request = requestBuilder.buildPageRequest(source: source, urlText: currentNext)
            let absolute = request.url.absoluteString
            guard !seenURLs.contains(absolute) else { break }
            seenURLs.insert(absolute)

            switch await loadWithOptionalWebViewFallback(request, source: source, stage: "toc.next.load") {
            case .success(let response):
                switch parseChapterListPage(source: source, book: book, response: response) {
                case .success(let page):
                    let offset = chapters.count
                    chapters.append(contentsOf: page.chapters.map { chapter in
                        BookChapter(
                            title: chapter.title,
                            url: chapter.url,
                            bookUrl: chapter.bookUrl,
                            index: offset + chapter.index,
                            isVip: chapter.isVip
                        )
                    })
                    nextURLText = page.nextTocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    pagesLoaded += 1
                case .failure(let error):
                    await emitFailure(error, stage: "toc.next.parse", source: source, details: ["url": response.url.absoluteString])
                    nextURLText = nil
                }
            case .failure(let error):
                await emitFailure(error, stage: "toc.next.load", source: source, details: ["url": absolute])
                nextURLText = nil
            }
        }

        return chapters.isEmpty ? .failure(.empty("Chapter list is empty")) : .success(chapters)
    }

    private func appendNextContentPages(
        _ firstPage: ChapterContent,
        source: BookSource,
        chapter: BookChapter,
        firstURL: URL,
        globalPurifyRules: [String]
    ) async -> Result<ChapterContent, SourceEngineError> {
        var paragraphs = firstPage.paragraphs
        var nextURLText = firstPage.nextContentUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var seenURLs: Set<String> = [firstURL.absoluteString]
        var finalNextURL = nextURLText
        var pagesLoaded = 1
        let maxPages = 8

        while let currentNext = nextURLText, pagesLoaded < maxPages {
            let request = requestBuilder.buildPageRequest(source: source, urlText: currentNext)
            let absolute = request.url.absoluteString
            guard !seenURLs.contains(absolute) else {
                finalNextURL = nil
                break
            }
            seenURLs.insert(absolute)

            switch await loadWithOptionalWebViewFallback(request, source: source, stage: "content.next.load") {
            case .success(let response):
                switch parseContentPage(
                    source: source,
                    chapter: chapter,
                    response: response,
                    globalPurifyRules: globalPurifyRules
                ) {
                case .success(let nextPage):
                    paragraphs.append(contentsOf: nextPage.paragraphs)
                    nextURLText = nextPage.nextContentUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    finalNextURL = nextURLText
                    pagesLoaded += 1
                case .failure(let error):
                    await emitFailure(error, stage: "content.next.parse", source: source, details: ["url": response.url.absoluteString])
                    nextURLText = nil
                    finalNextURL = currentNext
                }
            case .failure(let error):
                await emitFailure(error, stage: "content.next.load", source: source, details: ["url": absolute])
                nextURLText = nil
                finalNextURL = currentNext
            }
        }

        return .success(ChapterContent(
            chapter: firstPage.chapter,
            title: firstPage.title,
            paragraphs: paragraphs,
            nextContentUrl: finalNextURL
        ))
    }

    private func bodyJSScript(_ source: BookSource) -> String? {
        for key in ["bodyJs", "bodyjs", "bodyJS"] {
            if let value = source.raw[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        guard let customConfig = source.customConfig,
              let data = customConfig.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["bodyJs", "bodyjs", "bodyJS"] {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func emitFailure(
        _ error: SourceEngineError,
        stage: String,
        source: BookSource,
        details: [String: String] = [:]
    ) async {
        await diagnostics.emit(.init(
            level: .warning,
            stage: stage,
            sourceName: source.bookSourceName,
            message: error.displayMessage,
            details: details
        ))
    }
}
