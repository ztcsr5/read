import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    let sourceStore: SourceStore
    let bookshelfStore: BookshelfStore
    let purifyRuleStore: PurifyRuleStore
    let chapterContentCacheStore: ChapterContentCacheStore
    let sourceHealthStore: SourceHealthStore
    let sourceWritingServer: LightweightHTTPServer
    private let injectedEngine: SourceEngine?
    private var cancellables: Set<AnyCancellable> = []
    lazy var engine: SourceEngine = {
        if let injectedEngine {
            return injectedEngine
        }
        return LegadoSourceEngine(
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

    init(
        sourceStore: SourceStore? = nil,
        bookshelfStore: BookshelfStore? = nil,
        purifyRuleStore: PurifyRuleStore? = nil,
        chapterContentCacheStore: ChapterContentCacheStore? = nil,
        sourceHealthStore: SourceHealthStore? = nil,
        engine: SourceEngine? = nil
    ) {
        self.sourceStore = sourceStore ?? SourceStore()
        self.bookshelfStore = bookshelfStore ?? BookshelfStore()
        self.purifyRuleStore = purifyRuleStore ?? PurifyRuleStore()
        self.chapterContentCacheStore = chapterContentCacheStore ?? ChapterContentCacheStore()
        self.sourceHealthStore = sourceHealthStore ?? SourceHealthStore()
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
                if ext == "json", let text = String(data: data, encoding: .utf8) {
                    let report = try sourceStore.importJSON(text)
                    record(DiagnosticEvent(level: .info, stage: "import", message: report.userMessage))
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

        sourceHealthStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }
}
