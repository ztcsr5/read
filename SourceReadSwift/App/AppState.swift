import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    let sourceStore: SourceStore
    let bookshelfStore: BookshelfStore
    let purifyRuleStore: PurifyRuleStore
    let chapterContentCacheStore: ChapterContentCacheStore
    let chapterDownloadStore: ChapterDownloadStore
    let chapterDownloadCoordinator: ChapterDownloadCoordinator
    let rssArticleStateStore: RSSArticleStateStore
    let rssFeedCacheStore: RSSFeedCacheStore
    let rssArticleContentCacheStore: RSSArticleContentCacheStore
    let sourceHealthStore: SourceHealthStore
    let sourceDiagnosticHistoryStore: SourceDiagnosticHistoryStore
    let sourceCookieStore: SourceCookieStore
    let sourceWritingServer: LightweightHTTPServer
    private let injectedEngine: SourceEngine?
    private var cancellables: Set<AnyCancellable> = []
    lazy var engine: SourceEngine = {
        if let injectedEngine {
            return injectedEngine
        }
        return LegadoSourceEngine(
            cookieStore: sourceCookieStore,
            diagnostics: DiagnosticSink { event in
                Task { @MainActor [weak self] in
                    self?.record(event)
                }
            },
            purifyRules: { [weak self] in
                await MainActor.run { [weak self] in
                    self?.purifyRuleStore.enabledPatterns ?? []
                }
            }
        )
    }()

    @Published var diagnostics: [DiagnosticEvent] = []
    @Published var isTabChromeHidden = false
    private var tabChromeOwner: UUID?

    init(
        sourceStore: SourceStore? = nil,
        bookshelfStore: BookshelfStore? = nil,
        purifyRuleStore: PurifyRuleStore? = nil,
        chapterContentCacheStore: ChapterContentCacheStore? = nil,
        chapterDownloadStore: ChapterDownloadStore? = nil,
        rssArticleStateStore: RSSArticleStateStore? = nil,
        rssFeedCacheStore: RSSFeedCacheStore? = nil,
        rssArticleContentCacheStore: RSSArticleContentCacheStore? = nil,
        sourceHealthStore: SourceHealthStore? = nil,
        sourceDiagnosticHistoryStore: SourceDiagnosticHistoryStore? = nil,
        sourceCookieStore: SourceCookieStore? = nil,
        engine: SourceEngine? = nil
    ) {
        self.sourceStore = sourceStore ?? SourceStore()
        self.bookshelfStore = bookshelfStore ?? BookshelfStore()
        self.purifyRuleStore = purifyRuleStore ?? PurifyRuleStore()
        self.chapterContentCacheStore = chapterContentCacheStore ?? ChapterContentCacheStore()
        let resolvedChapterDownloadStore = chapterDownloadStore ?? ChapterDownloadStore()
        self.chapterDownloadStore = resolvedChapterDownloadStore
        self.chapterDownloadCoordinator = ChapterDownloadCoordinator(store: resolvedChapterDownloadStore)
        self.rssArticleStateStore = rssArticleStateStore ?? RSSArticleStateStore()
        self.rssFeedCacheStore = rssFeedCacheStore ?? RSSFeedCacheStore()
        self.rssArticleContentCacheStore = rssArticleContentCacheStore ?? RSSArticleContentCacheStore()
        self.sourceHealthStore = sourceHealthStore ?? SourceHealthStore()
        self.sourceDiagnosticHistoryStore = sourceDiagnosticHistoryStore ?? SourceDiagnosticHistoryStore()
        self.sourceCookieStore = sourceCookieStore ?? SourceCookieStore()
        self.sourceWritingServer = LightweightHTTPServer()
        self.injectedEngine = engine
        bindChildStores()
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics.insert(event, at: 0)
        if diagnostics.count > 200 {
            diagnostics.removeLast(diagnostics.count - 200)
        }
    }

    func acquireTabChromeHidden(owner: UUID) {
        tabChromeOwner = owner
        isTabChromeHidden = true
    }

    func releaseTabChromeHidden(owner: UUID? = nil) {
        if let owner, tabChromeOwner != owner { return }
        tabChromeOwner = nil
        isTabChromeHidden = false
    }

    func importSharedDocument(_ url: URL) {
        do {
            let localURL = try PickedDocumentAccess.copiedURL(from: url)
            let ext = localURL.pathExtension.lowercased()
            if ext == "epub" {
                let parsed = try LocalEPUBBookParser().parse(fileURL: localURL)
                bookshelfStore.addLocalTextBook(parsed)
                record(DiagnosticEvent(level: .info, stage: "import", sourceName: parsed.title, message: "已导入 EPUB"))
            } else {
                let data = try Data(contentsOf: localURL)
                if shouldTrySourceImport(fileExtension: ext, data: data) {
                    do {
                        let report = try sourceStore.importJSONData(data)
                        record(DiagnosticEvent(level: .info, stage: "import", message: report.userMessage))
                    } catch where ext != "json" {
                        let parsed = LocalTextBookParser().parse(data: data, fileName: localURL.lastPathComponent)
                        bookshelfStore.addLocalTextBook(parsed)
                        record(DiagnosticEvent(level: .info, stage: "import", sourceName: parsed.title, message: "已导入本地文本"))
                    }
                } else {
                    let parsed = LocalTextBookParser().parse(data: data, fileName: localURL.lastPathComponent)
                    bookshelfStore.addLocalTextBook(parsed)
                    record(DiagnosticEvent(level: .info, stage: "import", sourceName: parsed.title, message: "已导入本地文本"))
                }
            }
        } catch {
            record(DiagnosticEvent(level: .error, stage: "import", message: "文件导入失败：\(error.localizedDescription)", details: ["file": url.lastPathComponent]))
        }
    }

    private func shouldTrySourceImport(fileExtension ext: String, data: Data) -> Bool {
        if ext == "json" { return true }
        guard ["", "txt", "text", "data"].contains(ext) else { return false }
        let text = ResponseTextDecoder()
            .decode(data: data.prefix(128_000), headers: [:])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return text.hasPrefix("{")
            || text.hasPrefix("[")
            || text.contains("bookSourceName")
            || text.contains("bookSourceUrl")
            || text.contains("ruleSearch")
    }

    private func bindChildStores() {
        sourceStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        bookshelfStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        purifyRuleStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        chapterContentCacheStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        chapterDownloadStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        rssArticleStateStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        rssFeedCacheStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        rssArticleContentCacheStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        sourceHealthStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        sourceDiagnosticHistoryStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }
}
