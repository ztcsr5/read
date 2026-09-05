import SwiftUI
import UIKit

struct BookDetailView: View {
    @EnvironmentObject private var appState: AppState
    let book: SearchBook
    @State private var detail: BookDetail?
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didOpenReader = false
    @State private var hasPromptedAddAfterPreview = false
    @State private var showAddAfterPreviewPrompt = false
    @State private var isAscending = true
    @State private var showAllChapters = false
    private var downloadRecord: ChapterDownloadRecord? {
        appState.chapterDownloadStore.record(bookID: book.id)
    }

    private var isDownloading: Bool {
        appState.chapterDownloadCoordinator.isRunning(bookID: book.id)
    }

    private var displayedChapters: [BookChapter] {
        Array((isAscending ? chapters : Array(chapters.reversed())).prefix(100))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SearchBookRow(
                    book: book,
                    onAdd: {
                        addCurrentBookToShelf()
                    },
                    isInBookshelf: appState.bookshelfStore.contains(book)
                )
                    .podcastCard()

                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在加载详情")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .podcastCard()
                } else if let errorMessage {
                    EmptyStateCard(
                        systemImage: "exclamationmark.triangle",
                        title: "详情加载失败",
                        message: errorMessage
                    )
                } else if let detail {
                    detailCard(detail)
                    chapterList
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { markAsRead() } label: {
                        Label("标记为已读", systemImage: "checkmark.circle")
                    }
                    Button { isAscending.toggle() } label: {
                        Label(isAscending ? "切换倒序" : "切换正序", systemImage: "arrow.up.arrow.down")
                    }
                    Button { Task { await reload() } } label: {
                        Label("刷新目录", systemImage: "arrow.clockwise")
                    }
                    Button { toggleDownload() } label: {
                        Label(downloadLabel, systemImage: isDownloading ? "stop.circle" : "arrow.down.circle")
                    }
                    .disabled(chapters.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("书籍操作")
            }
        }
        .task {
            await load()
        }
        .sheet(isPresented: $showAllChapters) {
            NavigationStack {
                List {
                    ForEach(isAscending ? chapters : Array(chapters.reversed())) { chapter in
                        NavigationLink {
                            ChapterLoadingView(
                                bookID: appState.bookshelfStore.contains(book) ? book.id : nil,
                                sourceUrl: book.sourceUrl,
                                chapter: chapter,
                                totalChapters: chapters.count,
                                chapters: chapters
                            )
                        } label: { Text(chapter.title).lineLimit(1) }
                    }
                }
                .navigationTitle("完整目录")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            promptToAddAfterPreviewIfNeeded()
        }
        .confirmationDialog(
            "加入书架？",
            isPresented: $showAddAfterPreviewPrompt,
            titleVisibility: .visible
        ) {
            Button("加入书架") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                addCurrentBookToShelf()
            }
            Button("暂不加入", role: .cancel) {}
        } message: {
            Text("如果这本书符合预期，可以加入书架，后续会记录阅读进度和更新状态。")
        }
    }

    private func detailCard(_ detail: BookDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.name)
                .font(.title.bold())
            Text(detail.author ?? "作者未知")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let intro = detail.intro, !intro.isEmpty {
                Text(intro)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
            }
            if let latest = detail.latestChapter {
                Text("最新：\(latest)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .podcastCard()
    }

    private var chapterList: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("目录")
                    .font(.title2.bold())
                Spacer()
                Text("\(chapters.count) 章")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(displayedChapters) { chapter in
                NavigationLink {
                    ChapterLoadingView(
                        bookID: appState.bookshelfStore.contains(book) ? book.id : nil,
                        sourceUrl: book.sourceUrl,
                        chapter: chapter,
                        totalChapters: chapters.count,
                        chapters: chapters
                    )
                } label: {
                    HStack {
                        Text(chapter.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .podcastCard()
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    didOpenReader = true
                })
            }
            if chapters.count > displayedChapters.count {
                Button {
                    showAllChapters = true
                } label: {
                    Label("查看全部 \(chapters.count) 章", systemImage: "list.number")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func load() async {
        guard detail == nil, !isLoading else { return }
        guard let source = appState.sourceStore.source(for: book.sourceUrl) else {
            errorMessage = "找不到书源：\(book.sourceName)"
            return
        }

        isLoading = true
        defer { isLoading = false }

        let engine = appState.engine
        let selectedBook = book
        let detailResult = await AsyncTimeout.run(seconds: 12) {
            await engine.getBookDetail(source: source, book: selectedBook)
        } ?? .failure(.network("Detail load timed out"))
        switch detailResult {
        case .success(let loadedDetail):
            detail = loadedDetail
            let chapterResult = await AsyncTimeout.run(seconds: 12) {
                await engine.getChapterList(source: source, book: loadedDetail)
            } ?? .failure(.network("Chapter list timed out"))
            switch chapterResult {
            case .success(let loadedChapters):
                chapters = loadedChapters
                if appState.bookshelfStore.contains(book) {
                    appState.bookshelfStore.updateDetails(
                        bookID: book.id,
                        latestChapterTitle: loadedDetail.latestChapter,
                        intro: loadedDetail.intro,
                        totalChapters: loadedChapters.count
                    )
                }
            case .failure(let error):
                errorMessage = "目录加载失败：\(error.displayMessage)"
            }
        case .failure(let error):
            errorMessage = error.displayMessage
        }
    }

    private func reload() async {
        detail = nil
        chapters = []
        errorMessage = nil
        await load()
    }

    private func markAsRead() {
        guard !chapters.isEmpty else { return }
        if !appState.bookshelfStore.contains(book) {
            appState.bookshelfStore.addOrUpdate(book)
        }
        appState.bookshelfStore.updateReadingProgress(
            bookID: book.id,
            chapterIndex: max(chapters.count - 1, 0),
            chapterTitle: chapters.last?.title,
            totalChapters: chapters.count
        )
    }

    private var downloadLabel: String {
        if isDownloading { return "停止缓存" }
        guard let record = downloadRecord else { return "缓存全本章节" }
        switch record.status {
        case .completed: return "全本已缓存"
        case .paused: return "继续缓存 \(record.completedCount)/\(record.chapterCount)"
        case .failed: return "重试缓存（失败 \(record.failedCount)）"
        case .cancelled, .queued, .running: return "继续缓存 \(record.completedCount)/\(record.chapterCount)"
        }
    }

    private func toggleDownload() {
        if isDownloading {
            appState.chapterDownloadCoordinator.cancel(bookID: book.id)
            return
        }
        guard !chapters.isEmpty,
              let source = appState.sourceStore.source(for: book.sourceUrl) else { return }
        appState.chapterDownloadCoordinator.start(
            bookID: book.id,
            source: source,
            title: book.name,
            chapters: chapters,
            engine: appState.engine,
            cacheStore: appState.chapterContentCacheStore,
            purifyRules: appState.purifyRuleStore.enabledPatterns
        )
    }

    private func addCurrentBookToShelf() {
        appState.bookshelfStore.addOrUpdate(book)
        if let detail {
            appState.bookshelfStore.updateDetails(
                bookID: book.id,
                latestChapterTitle: detail.latestChapter,
                intro: detail.intro,
                totalChapters: chapters.count
            )
        }
    }

    private func promptToAddAfterPreviewIfNeeded() {
        guard didOpenReader else { return }
        didOpenReader = false
        guard !hasPromptedAddAfterPreview,
              !appState.bookshelfStore.contains(book) else { return }
        hasPromptedAddAfterPreview = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showAddAfterPreviewPrompt = true
        }
    }
}

struct ChapterLoadingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let bookID: String?
    let sourceUrl: String
    let chapter: BookChapter
    var totalChapters: Int? = nil
    var chapters: [BookChapter] = []
    var extraToolbarActions: () -> AnyView = { AnyView(EmptyView()) }
    var onRequestSourceSwitch: (() -> Void)?
    @State private var content: ChapterContent?
    @State private var currentChapter: BookChapter?
    @State private var errorMessage: String?
    @State private var isUsingStaleCache = false
    @State private var isCachingNext = false
    @State private var autoplaySpeechAfterHandoff = false
    @State private var autoplayAutoScrollAfterHandoff = false
    @State private var showReaderChromeAfterChapterSelection = false
    @State private var preloadTask: Task<Void, Never>?
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount

    private var effectiveChapter: BookChapter {
        currentChapter ?? chapter
    }

    var body: some View {
        Group {
            if let loadedContent = content {
                readerView(loadedContent)
            } else if let errorMessage {
                chapterLoadErrorView(errorMessage)
            } else {
                chapterLoadingView
            }
        }
        .overlay(alignment: .top) {
            if isCachingNext {
                Text("Caching next chapters...")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassPanel(cornerRadius: 14, material: .thinMaterial, shadowOpacity: 0.08)
                    .padding(.top, 14)
            }
        }
        .task {
            await load()
        }
        .onChange(of: currentChapter) { _ in
            Task {
                await load(force: true)
            }
        }
        .onDisappear {
            preloadTask?.cancel()
            preloadTask = nil
        }
    }

    private func load(force: Bool = false, ignoreCache: Bool = false) async {
        if force {
            content = nil
            errorMessage = nil
            isUsingStaleCache = false
        }
        guard content == nil, errorMessage == nil else { return }
        guard let source = appState.sourceStore.source(for: sourceUrl) else {
            errorMessage = "找不到书源"
            return
        }
        let purifyRules = appState.purifyRuleStore.enabledPatterns
        let targetChapter = effectiveChapter
        if !ignoreCache, let cached = appState.chapterContentCacheStore.content(
            sourceURL: source.bookSourceUrl,
            chapter: targetChapter,
            purifyRules: purifyRules
        ) {
            content = cached
            isUsingStaleCache = false
            preloadNextChapters(after: targetChapter, source: source, purifyRules: purifyRules)
            return
        }
        let engine = appState.engine
        let contentResult = await AsyncTimeout.run(seconds: 14) {
            await engine.getContent(source: source, chapter: targetChapter)
        } ?? .failure(.network("Content load timed out"))
        switch contentResult {
        case .success(let loaded):
            appState.chapterContentCacheStore.save(loaded, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
            content = loaded
            isUsingStaleCache = false
            preloadNextChapters(after: targetChapter, source: source, purifyRules: purifyRules)
        case .failure(let error):
            if let cached = appState.chapterContentCacheStore.staleContent(
                sourceURL: source.bookSourceUrl,
                chapter: targetChapter
            ) {
                content = cached
                isUsingStaleCache = true
            } else {
                errorMessage = error.displayMessage
            }
        }
    }

    private func preloadNextChapters(after chapter: BookChapter, source: BookSource, purifyRules: [String]) {
        let count = ReaderPreloadPolicy.clamp(preloadChapterCount)
        guard count > 0 else { return }
        guard preloadTask == nil else { return }
        let nextChapters = chapters
            .filter { $0.index > chapter.index }
            .sorted { $0.index < $1.index }
            .prefix(count)
            .filter {
                !appState.chapterContentCacheStore.isCached(
                    sourceURL: source.bookSourceUrl,
                    chapter: $0,
                    purifyRules: purifyRules
                )
            }
        guard !nextChapters.isEmpty else { return }
        let engine = appState.engine
        preloadTask = Task {
            for next in nextChapters {
                guard !Task.isCancelled else { return }
                let result = await AsyncTimeout.run(seconds: 10) {
                    await engine.getContent(source: source, chapter: next)
                } ?? .failure(.network("Preload timed out"))
                guard !Task.isCancelled else { return }
                if case .success(let loaded) = result {
                    await MainActor.run {
                        appState.chapterContentCacheStore.save(
                            loaded,
                            sourceURL: source.bookSourceUrl,
                            purifyRules: purifyRules
                        )
                    }
                }
            }
            await MainActor.run {
                preloadTask = nil
            }
        }
    }

    private func readerView(_ loadedContent: ChapterContent) -> some View {
        ReaderView(
            bookID: bookID ?? "\(sourceUrl)|\(chapter.bookUrl)",
            content: loadedContent,
            chapterIndex: effectiveChapter.index,
            totalChapters: totalChapters,
            chapters: chapters,
            statusMessage: isUsingStaleCache ? "网络加载失败，正在显示本地缓存副本" : nil,
            extraToolbarActions: extraToolbarActions,
            onRequestSourceSwitch: onRequestSourceSwitch,
            onRequestBookDetail: { dismiss() },
            onSelectChapter: { selected in
                showReaderChromeAfterChapterSelection = true
                currentChapter = selected
                content = nil
                errorMessage = nil
                isUsingStaleCache = false
            },
            onRefreshChapter: {
                Task { await load(force: true, ignoreCache: true) }
            },
            onCacheNextChapters: {
                Task { await cacheNextChaptersFromReader() }
            },
            onSpeechFinished: {
                guard let next = chapters.first(where: { $0.index == effectiveChapter.index + 1 }) else { return }
                autoplaySpeechAfterHandoff = true
                currentChapter = next
                content = nil
                errorMessage = nil
                isUsingStaleCache = false
            },
            autoplaySpeechOnAppear: autoplaySpeechAfterHandoff,
            onSpeechAutoplayConsumed: { autoplaySpeechAfterHandoff = false },
            autoplayAutoScrollOnAppear: autoplayAutoScrollAfterHandoff,
            onAutoScrollAutoplayConsumed: { autoplayAutoScrollAfterHandoff = false },
            onAutoScrollFinished: {
                autoplayAutoScrollAfterHandoff = true
            },
            initialOverlayVisible: showReaderChromeAfterChapterSelection
        )
        .id("reader-\(effectiveChapter.url)")
    }

    private func cacheNextChapters(after chapter: BookChapter, source: BookSource, purifyRules: [String]) async {
        let count = ReaderPreloadPolicy.clamp(preloadChapterCount)
        guard count > 0 else { return }
        let nextChapters = chapters
            .filter { $0.index > chapter.index }
            .sorted { $0.index < $1.index }
            .prefix(count)
            .filter {
                !appState.chapterContentCacheStore.isCached(
                    sourceURL: source.bookSourceUrl,
                    chapter: $0,
                    purifyRules: purifyRules
                )
        }
        let engine = appState.engine
        for next in nextChapters {
            let result = await AsyncTimeout.run(seconds: 10) {
                await engine.getContent(source: source, chapter: next)
            } ?? .failure(.network("Cache timed out"))
            if case .success(let loaded) = result {
                appState.chapterContentCacheStore.save(
                    loaded,
                    sourceURL: source.bookSourceUrl,
                    purifyRules: purifyRules
                )
            }
        }
    }

    private var chapterLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                Text("正在加载正文")
                    .font(.headline)
                Text(effectiveChapter.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(AppTheme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
    }

    private func cacheNextChaptersFromReader() async {
        guard !isCachingNext else { return }
        guard let source = appState.sourceStore.source(for: sourceUrl) else { return }
        isCachingNext = true
        defer { isCachingNext = false }
        await cacheNextChapters(after: effectiveChapter, source: source, purifyRules: appState.purifyRuleStore.enabledPatterns)
    }

    private func chapterLoadErrorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            EmptyStateCard(systemImage: "xmark.octagon", title: "正文加载失败", message: message)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                UIPasteboard.general.string = chapterDiagnosticText(message)
            } label: {
                Label("Copy diagnostics", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await load(force: true, ignoreCache: true) }
            } label: {
                Label("重试当前章节", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let onRequestSourceSwitch {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRequestSourceSwitch()
                } label: {
                    Label("换源继续阅读", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(AppTheme.pagePadding)
        .pageBackground()
    }

    private func chapterDiagnosticText(_ message: String) -> String {
        [
            "Chapter load failed",
            "sourceUrl: \(sourceUrl)",
            "bookUrl: \(effectiveChapter.bookUrl)",
            "chapterIndex: \(effectiveChapter.index)",
            "chapterTitle: \(effectiveChapter.title)",
            "chapterUrl: \(effectiveChapter.url)",
            "message: \(message)"
        ].joined(separator: "\n")
    }

    init(
        bookID: String? = nil,
        sourceUrl: String,
        chapter: BookChapter,
        totalChapters: Int? = nil,
        chapters: [BookChapter] = [],
        extraToolbarActions: @escaping () -> AnyView = { AnyView(EmptyView()) },
        onRequestSourceSwitch: (() -> Void)? = nil
    ) {
        self.bookID = bookID
        self.sourceUrl = sourceUrl
        self.chapter = chapter
        self.totalChapters = totalChapters
        self.chapters = chapters
        self.extraToolbarActions = extraToolbarActions
        self.onRequestSourceSwitch = onRequestSourceSwitch
    }
}
