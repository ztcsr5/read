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
        .task {
            await load()
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

            ForEach(chapters) { chapter in
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

        switch await appState.engine.getBookDetail(source: source, book: book) {
        case .success(let loadedDetail):
            detail = loadedDetail
            switch await appState.engine.getChapterList(source: source, book: loadedDetail) {
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
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount

    private var effectiveChapter: BookChapter {
        currentChapter ?? chapter
    }

    var body: some View {
        Group {
            if let loadedContent = content {
                ReaderView(
                    bookID: bookID ?? "\(sourceUrl)|\(chapter.bookUrl)",
                    content: loadedContent,
                    chapterIndex: effectiveChapter.index,
                    totalChapters: totalChapters,
                    chapters: chapters,
                    statusMessage: isUsingStaleCache ? "网络加载失败，正在显示本地缓存副本" : nil,
                    extraToolbarActions: extraToolbarActions,
                    onRequestSourceSwitch: onRequestSourceSwitch,
                    onSelectChapter: { selected in
                        currentChapter = selected
                        content = nil
                        errorMessage = nil
                        isUsingStaleCache = false
                    }
                )
            } else if let errorMessage {
                chapterLoadErrorView(errorMessage)
            } else {
                chapterLoadingView
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
    }

    private func load(force: Bool = false) async {
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
        if let cached = appState.chapterContentCacheStore.content(
            sourceURL: source.bookSourceUrl,
            chapter: effectiveChapter,
            purifyRules: purifyRules
        ) {
            content = cached
            isUsingStaleCache = false
            preloadNextChapters(after: effectiveChapter, source: source, purifyRules: purifyRules)
            return
        }
        switch await appState.engine.getContent(source: source, chapter: effectiveChapter) {
        case .success(let loaded):
            appState.chapterContentCacheStore.save(loaded, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
            content = loaded
            isUsingStaleCache = false
            preloadNextChapters(after: effectiveChapter, source: source, purifyRules: purifyRules)
        case .failure(let error):
            if let cached = appState.chapterContentCacheStore.staleContent(
                sourceURL: source.bookSourceUrl,
                chapter: effectiveChapter
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
        Task {
            for next in nextChapters {
                let result = await appState.engine.getContent(source: source, chapter: next)
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

    private func chapterLoadErrorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            EmptyStateCard(systemImage: "xmark.octagon", title: "正文加载失败", message: message)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await load(force: true) }
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
