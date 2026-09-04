import Foundation

protocol SourceEngine: Sendable {
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError>
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError>
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError>
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError>
    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError>
}

struct SourceLoginVerification: Equatable, Sendable {
    enum Status: String, Sendable, Equatable {
        case notConfigured
        case passed
        case requiresLogin
        case verificationRequired
        case blocked
        case warning
    }

    let status: Status
    let message: String
    let cookiePresent: Bool
}

extension SourceLoginVerification.Status {
    var displayTitle: String {
        switch self {
        case .notConfigured: return "INFO"
        case .passed: return "PASS"
        case .requiresLogin: return "LOGIN"
        case .verificationRequired: return "VERIFY"
        case .blocked: return "BLOCKED"
        case .warning: return "WARN"
        }
    }

    var healthStatus: SourceHealthStatus {
        switch self {
        case .notConfigured: return .warning
        case .passed: return .passed
        case .requiresLogin: return .requiresLogin
        case .verificationRequired: return .verificationRequired
        case .blocked: return .blocked
        case .warning: return .warning
        }
    }
}

extension SourceEngine {
    /// Engines that do not expose a login check remain fully source-compatible.
    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .success(SourceLoginVerification(status: .notConfigured, message: "未配置 loginCheckJs", cookiePresent: false))
    }
}

final class LegadoSourceEngine: SourceEngine, @unchecked Sendable {
    private let network: SourceNetworkClient
    private let diagnostics: DiagnosticSink
    private let cookieStore: SourceCookieStore
    private let purifyRules: () async -> [String]
    private let stateLock = NSLock()
    private var states: [String: RulePersistentState] = [:]
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
        let executionState = persistentState(for: source)
        let executionContext = RuleExecutionContext(persistentState: executionState, logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "search.js", sourceName: source.bookSourceName, message: message)) }
        })
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot()
            )
        }
        executionContext.responseHandler = { encoded in
            SynchronousSourceLoader().loadResponse(
                urlText: encoded,
                source: source,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: executionState.snapshot()
            )
        }
        await diagnostics.emit(.init(
            level: .info,
            stage: "search.prepare",
            sourceName: source.bookSourceName,
            message: "\u{51c6}\u{5907}\u{641c}\u{7d22}",
            details: ["keyword": keyword, "page": String(page)]
        ))

        let searchUrl: String
        switch searchURLResolver.resolve(source: source, keyword: keyword, page: page, persistentState: executionState) {
        case .success(let value):
            searchUrl = value
        case .failure(let error):
            await emitFailure(error, stage: "search.url", source: source)
            return .failure(error)
        }

        let request = requestBuilder.buildSearchRequest(
            source: source,
            searchUrl: searchUrl,
            keyword: keyword,
            page: page,
            persistentValues: executionState.snapshot()
        )
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "search.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleSearch])
            guard !transformedResponse.body.isEmpty else {
                let error = SourceEngineError.empty("\u{641c}\u{7d22}\u{54cd}\u{5e94}\u{4e3a}\u{7a7a}")
                await emitFailure(error, stage: "search.empty", source: source, details: ["url": transformedResponse.url.absoluteString])
                return .failure(error)
            }
            let parsed = SearchResultParser(executionContext: executionContext).parse(source: source, response: transformedResponse)
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
        let executionContext = RuleExecutionContext(persistentState: persistentState(for: source), logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "detail.js", sourceName: source.bookSourceName, message: message)) }
        })
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: persistentState(for: source).snapshot()
            )
        }
        executionContext.responseHandler = { encoded in
            SynchronousSourceLoader().loadResponse(
                urlText: encoded,
                source: source,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: persistentState(for: source).snapshot()
            )
        }
        let request = requestBuilder.buildPageRequest(
            source: source,
            urlText: book.bookUrl,
            persistentValues: persistentState(for: source).snapshot()
        )
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "detail.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleBookInfo])
            let parsed = BookDetailParser(executionContext: executionContext).parse(source: source, book: book, response: transformedResponse)
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
        let executionContext = RuleExecutionContext(persistentState: persistentState(for: source), logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "toc.js", sourceName: source.bookSourceName, message: message)) }
        })
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: persistentState(for: source).snapshot()
            )
        }
        executionContext.responseHandler = { encoded in
            SynchronousSourceLoader().loadResponse(
                urlText: encoded,
                source: source,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: persistentState(for: source).snapshot()
            )
        }
        let tocURL = book.tocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? book.bookUrl
        let request = requestBuilder.buildPageRequest(
            source: source,
            urlText: tocURL,
            persistentValues: persistentState(for: source).snapshot()
        )
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "toc.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleToc])
            let parsed = parseChapterListPage(source: source, book: book, response: transformedResponse, executionContext: executionContext)
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
                firstURL: response.url,
                executionContext: executionContext
            )
        case .failure(let error):
            await emitFailure(error, stage: "toc.load", source: source, details: ["url": request.url.absoluteString])
            return .failure(error)
        }
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        let executionContext = RuleExecutionContext(persistentState: persistentState(for: source), logHandler: { [diagnostics] message in
            Task { await diagnostics.emit(.init(level: .info, stage: "content.js", sourceName: source.bookSourceName, message: message)) }
        })
        executionContext.networkHandler = { [network] encoded in
            self.syncLoad(
                encoded: encoded,
                source: source,
                network: network,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: persistentState(for: source).snapshot()
            )
        }
        executionContext.responseHandler = { encoded in
            SynchronousSourceLoader().loadResponse(
                urlText: encoded,
                source: source,
                cookieHeader: executionContext.string(for: "cookieHeader"),
                persistentValues: persistentState(for: source).snapshot()
            )
        }
        let request = requestBuilder.buildPageRequest(
            source: source,
            urlText: chapter.url,
            persistentValues: persistentState(for: source).snapshot()
        )
        let globalPurifyRules = await purifyRules()
        switch await loadWithOptionalWebViewFallback(request, source: source, stage: "content.load") {
        case .success(let response):
            let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleContent])
            let parsed = parseContentPage(
                source: source,
                chapter: chapter,
                response: transformedResponse,
                globalPurifyRules: globalPurifyRules,
                executionContext: executionContext
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
                globalPurifyRules: globalPurifyRules,
                executionContext: executionContext
            )
        case .failure(let error):
            await emitFailure(error, stage: "content.load", source: source, details: ["url": request.url.absoluteString])
            return .failure(error)
        }
    }

    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        guard let script = source.loginCheckJs?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return .success(SourceLoginVerification(status: .notConfigured, message: "未配置 loginCheckJs", cookiePresent: false))
        }
        guard let baseURL = URL(string: source.bookSourceUrl),
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? "") else {
            return .failure(.invalidSource("书源 URL 无法用于登录检查"))
        }
        let cookieHeader = await cookieStore.cookieHeader(for: baseURL)
        let context = RuleExecutionContext(
            initialValues: [
                "source": source,
                "baseUrl": baseURL.absoluteString,
                "cookieHeader": cookieHeader ?? ""
            ],
            persistentState: persistentState(for: source),
            networkHandler: { encoded in
                SynchronousSourceLoader().loadResponse(urlText: encoded, source: source, cookieHeader: cookieHeader)?.body ?? ""
            },
            responseHandler: { encoded in
                SynchronousSourceLoader().loadResponse(urlText: encoded, source: source, cookieHeader: cookieHeader)
            },
            logHandler: { [diagnostics] message in
                Task { await diagnostics.emit(.init(level: .info, stage: "loginCheck.js", sourceName: source.bookSourceName, message: message)) }
            }
        )
        let runtime = JSCoreRuntime(executionContext: context)
        let evaluated = runtime.evaluate(script, variables: [
            "source": source,
            "baseUrl": baseURL.absoluteString,
            "cookieHeader": cookieHeader ?? ""
        ])
        let value: String
        switch evaluated {
        case .success(let output):
            value = String(output).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        case .failure(let error):
            return .failure(error)
        }
        let normalized = value.lowercased()
        let status: SourceLoginVerification.Status
        if normalized.isEmpty || ["false", "0", "null", "undefined", "未登录", "请登录"].contains(normalized) {
            status = .requiresLogin
        } else if ["cloudflare", "captcha", "challenge", "安全验证", "人机验证"].contains(where: normalized.contains) {
            status = .verificationRequired
        } else if ["403", "429", "forbidden", "blocked", "拒绝访问"].contains(where: normalized.contains) {
            status = .blocked
        } else if ["true", "1", "ok", "success", "已登录", "登录成功"].contains(normalized) {
            status = .passed
        } else {
            status = .warning
        }
        return .success(SourceLoginVerification(
            status: status,
            message: value.isEmpty ? "loginCheckJs 返回空值" : "loginCheckJs 返回：\(value.prefix(160))",
            cookiePresent: !(cookieHeader?.isEmpty ?? true)
        ))
    }

    private func loadWithOptionalWebViewFallback(
        _ request: SourceRequest,
        source: BookSource,
        stage: String
    ) async -> Result<SourceResponse, SourceEngineError> {
        let primary = await network.load(request)
        if case .success(let response) = primary {
            await emitResponseObservation(response, request: request, source: source, stage: stage)
            if !shouldUseWebViewFallback(source: source, response: response) {
                return .success(response)
            }
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

    private func transformBodyIfNeeded(_ response: SourceResponse, source: BookSource, rules: [SourceRule?] = []) -> SourceResponse {
        var scripts: [String] = []
        if let sourceScript = bodyJSScript(source) { scripts.append(sourceScript) }
        for rule in rules {
            if let script = bodyJSScript(rule) { scripts.append(script) }
        }
        guard !scripts.isEmpty else { return response }
        let state = persistentState(for: source)
        let context = RuleExecutionContext(
            initialValues: ["baseUrl": response.url.absoluteString, "source": source],
            persistentState: state,
            networkHandler: { encoded in
                SynchronousSourceLoader().load(
                    urlText: encoded,
                    source: source,
                    cookieHeader: state.get("cookieHeader").nilIfEmpty,
                    persistentValues: state.snapshot()
                )
            }
        )
        context.responseHandler = { encoded in
            SynchronousSourceLoader().loadResponse(
                urlText: encoded,
                source: source,
                cookieHeader: context.string(for: "cookieHeader"),
                persistentValues: state.snapshot()
            )
        }
        var output = response.body
        for script in scripts {
            let variables: [String: Any] = [
                "result": output,
                "html": output,
                "body": output,
                "baseUrl": response.url.absoluteString,
                "source": source
            ]
            let runtime = JSCoreRuntime(executionContext: context)
            let evaluated = runtime.evaluate(script, variables: variables)
            let result: Result<String, SourceEngineError>
            if case .failure(.javascript) = evaluated, script.contains("return") {
                result = runtime.evaluate("(function(){\(script)})()", variables: variables)
            } else {
                result = evaluated
            }
            guard case .success(let value) = result else { continue }
            let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { output = value }
        }
        guard output != response.body else { return response }
        return SourceResponse(url: response.url, statusCode: response.statusCode, headers: response.headers, body: output, data: Data(output.utf8))
    }

    private func parseContentPage(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String],
        executionContext: RuleExecutionContext = RuleExecutionContext()
    ) -> Result<ChapterContent, SourceEngineError> {
        return ContentParser(executionContext: executionContext).parse(
            source: source,
            chapter: chapter,
            response: response,
            globalPurifyRules: globalPurifyRules
        )
    }

    private func parseChapterListPage(
        source: BookSource,
        book: BookDetail,
        response: SourceResponse,
        executionContext: RuleExecutionContext = RuleExecutionContext()
    ) -> Result<ChapterListPage, SourceEngineError> {
        return ChapterListParser(executionContext: executionContext).parsePage(source: source, book: book, response: response)
    }

    private func syncLoad(
        encoded: String,
        source: BookSource,
        network: SourceNetworkClient,
        cookieHeader: String? = nil,
        persistentValues: [String: String] = [:]
    ) -> String {
        // JavaScriptCore callbacks are synchronous. Calling async `network.load` and
        // waiting on a semaphore can deadlock when the callback is already running on
        // the cooperative executor, so use the dedicated synchronous loader here.
        _ = network // kept in the signature for source-engine injection compatibility
        return SynchronousSourceLoader().load(
            urlText: encoded,
            source: source,
            cookieHeader: cookieHeader,
            persistentValues: persistentValues
        )
    }

    private func appendNextChapterListPages(
        _ firstPage: ChapterListPage,
        source: BookSource,
        book: BookDetail,
        firstURL: URL,
        executionContext: RuleExecutionContext
    ) async -> Result<[BookChapter], SourceEngineError> {
        var chapters = firstPage.chapters
        var nextURLText = firstPage.nextTocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var seenURLs: Set<String> = [firstURL.absoluteString]
        var pagesLoaded = 1
        let maxPages = 30

        while let currentNext = nextURLText, pagesLoaded < maxPages {
            let request = requestBuilder.buildPageRequest(
                source: source,
                urlText: currentNext,
                persistentValues: persistentState(for: source).snapshot()
            )
            let absolute = request.url.absoluteString
            guard !seenURLs.contains(absolute) else { break }
            seenURLs.insert(absolute)

            switch await loadWithOptionalWebViewFallback(request, source: source, stage: "toc.next.load") {
            case .success(let response):
                let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleToc])
                switch parseChapterListPage(source: source, book: book, response: transformedResponse, executionContext: executionContext) {
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
        globalPurifyRules: [String],
        executionContext: RuleExecutionContext
    ) async -> Result<ChapterContent, SourceEngineError> {
        var paragraphs = firstPage.paragraphs
        var nextURLText = firstPage.nextContentUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var seenURLs: Set<String> = [firstURL.absoluteString]
        var finalNextURL = nextURLText
        var pagesLoaded = 1
        let maxPages = 8

        while let currentNext = nextURLText, pagesLoaded < maxPages {
            let request = requestBuilder.buildPageRequest(
                source: source,
                urlText: currentNext,
                persistentValues: persistentState(for: source).snapshot()
            )
            let absolute = request.url.absoluteString
            guard !seenURLs.contains(absolute) else {
                finalNextURL = nil
                break
            }
            seenURLs.insert(absolute)

            switch await loadWithOptionalWebViewFallback(request, source: source, stage: "content.next.load") {
            case .success(let response):
                let transformedResponse = transformBodyIfNeeded(response, source: source, rules: [source.ruleContent])
                switch parseContentPage(
                    source: source,
                    chapter: chapter,
                    response: transformedResponse,
                    globalPurifyRules: globalPurifyRules,
                    executionContext: executionContext
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

    private func bodyJSScript(_ rule: SourceRule?) -> String? {
        guard let rule else { return nil }
        for key in ["bodyJs", "bodyjs", "bodyJS"] {
            if let value = rule.fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
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

    private func emitResponseObservation(
        _ response: SourceResponse,
        request: SourceRequest,
        source: BookSource,
        stage: String
    ) async {
        let contentType = response.headers.first {
            $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value ?? ""
        let hasCookie = response.headers.contains {
            $0.key.caseInsensitiveCompare("Set-Cookie") == .orderedSame
        }
        await diagnostics.emit(.init(
            level: .info,
            stage: "\(stage).response",
            sourceName: source.bookSourceName,
            message: "收到书源响应",
            details: [
                "method": request.method.rawValue,
                "url": response.url.absoluteString,
                "status": String(response.statusCode),
                "bytes": String(response.data.count),
                "contentType": contentType,
                "setCookie": hasCookie ? "present" : "absent"
            ]
        ))
    }

    private func persistentState(for source: BookSource) -> RulePersistentState {
        let key = source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        stateLock.lock()
        defer { stateLock.unlock() }
        if let state = states[key] { return state }
        let state = RulePersistentState()
        states[key] = state
        return state
    }
}
