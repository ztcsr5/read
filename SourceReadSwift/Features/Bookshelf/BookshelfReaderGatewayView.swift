import SwiftUI

struct BookshelfReaderGatewayView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let book: BookshelfBook
    var initialBookmark: ReaderBookmark? = nil
    var initialChapterIndex: Int? = nil

    @State private var detail: BookDetail?
    @State private var chapters: [BookChapter] = []
    @State private var selectedChapter: BookChapter?
    @State private var selectedLocalChapterIndex: Int?
    @State private var errorMessage: String?
    @State private var showSourceSwitcher = false
    @State private var sourceSwitchState = SourceSwitchState()
    @State private var autoplaySpeechAfterHandoff = false
    @State private var autoplayAutoScrollAfterHandoff = false
    @State private var showReaderChromeAfterChapterSelection = false
    @State private var didApplyInitialBookmark = false
    @State private var didApplyInitialChapter = false
    @State private var requestedChapterIndex: Int?
    @State private var sourceSwitchSearchTrigger = 0
    @State private var localNavigationRevision = 0

    private var currentBook: BookshelfBook {
        appState.bookshelfStore.book(id: book.id) ?? book
    }

    var body: some View {
        gatewayContent
        .task {
            appState.bookshelfStore.markUpdatesSeen(bookID: book.id)
            applyInitialBookmarkIfNeeded()
            applyInitialChapterIfNeeded()
            await resumeReading()
        }
        .sheet(isPresented: $showSourceSwitcher) {
            sourceSwitcherSheet
        }
    }

    private var gatewayContent: AnyView {
        if !localBookChapters.isEmpty {
            return AnyView(localReader)
        } else if let localContent = book.localContent {
            return AnyView(
                ReaderView(
                    bookID: book.id,
                    content: ChapterContent(
                        chapter: BookChapter(title: "全文", url: book.bookURL, bookUrl: book.bookURL, index: 0, isVip: false),
                        title: book.title,
                        paragraphs: localContent,
                        nextContentUrl: nil
                    ),
                    chapterIndex: 0,
                    totalChapters: 1
                )
            )
        } else if let selectedChapter {
            return AnyView(
                ChapterLoadingView(
                    bookID: book.id,
                    sourceUrl: currentBook.sourceURL,
                    chapter: selectedChapter,
                    totalChapters: chapters.count,
                    chapters: chapters,
                    extraToolbarActions: {
                        AnyView(
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showSourceSwitcher = true
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title3.weight(.semibold))
                                    .frame(width: 44, height: 44)
                            }
                        )
                    },
                    onRequestSourceSwitch: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showSourceSwitcher = true
                    }
                )
            )
        } else if let errorMessage {
            return AnyView(readerRecoveryErrorView(errorMessage))
        } else {
            return AnyView(
                ProgressView("正在恢复阅读进度")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pageBackground()
            )
        }
    }

    private var localBookChapters: [LocalTextChapter] {
        book.localChapters ?? []
    }

    private var localNavigationEntries: [LocalTextNavigationEntry] {
        currentBook.localNavigationEntries ?? []
    }

    private func applyInitialBookmarkIfNeeded() {
        guard !didApplyInitialBookmark, let initialBookmark else { return }
        didApplyInitialBookmark = true
        if !localBookChapters.isEmpty {
            selectedLocalChapterIndex = initialBookmark.chapterIndex
        }
        appState.bookshelfStore.updateReadingProgress(
            bookID: book.id,
            chapterIndex: initialBookmark.chapterIndex,
            chapterTitle: initialBookmark.chapterTitle,
            totalChapters: max(currentBook.totalChapters, initialBookmark.chapterIndex + 1),
            paragraphIndex: initialBookmark.paragraphIndex
        )
    }

    private func applyInitialChapterIfNeeded() {
        guard !didApplyInitialChapter, let initialChapterIndex else { return }
        didApplyInitialChapter = true
        requestedChapterIndex = max(0, initialChapterIndex)
    }

    private func readerRecoveryErrorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            EmptyStateCard(systemImage: "xmark.octagon", title: "阅读恢复失败", message: message)

            Button {
                showSourceSwitcher = true
            } label: {
                Label("尝试换源继续阅读", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                errorMessage = nil
                selectedChapter = nil
                chapters = []
                Task { await resumeReading() }
            } label: {
                Label("重试当前书源", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(AppTheme.pagePadding)
        .pageBackground()
    }

    private var localReader: some View {
        let chapters = localBookChapters
        let requestedIndex = selectedLocalChapterIndex ?? requestedChapterIndex ?? currentBook.currentChapterIndex
        let safeIndex = min(max(requestedIndex, 0), max(chapters.count - 1, 0))
        let localChapter = chapters[safeIndex]
        let fallbackChapters = chapters.map {
            BookChapter(
                title: $0.title,
                url: "\(book.bookURL)#\($0.index)",
                bookUrl: book.bookURL,
                index: $0.index,
                isVip: false
            )
        }
        let storedParagraph = currentBook.currentChapterIndex == safeIndex ? currentBook.currentParagraphIndex : nil
        let initialParagraphIndex = storedParagraph
        return ReaderView(
            bookID: book.id,
            content: ChapterContent(
                chapter: fallbackChapters[safeIndex],
                title: localChapter.title,
                paragraphs: localChapter.paragraphs,
                nextContentUrl: nil
            ),
            chapterIndex: safeIndex,
            totalChapters: chapters.count,
            chapters: fallbackChapters,
            navigationEntries: localNavigationEntries,
            initialParagraphIndex: initialParagraphIndex,
            onRequestBookDetail: {
                dismiss()
            },
            onSelectChapter: { chapter in
                showReaderChromeAfterChapterSelection = true
                selectedLocalChapterIndex = chapter.index
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: chapter.index,
                    chapterTitle: chapter.title,
                    totalChapters: chapters.count
                )
            },
            onSelectNavigationEntry: { entry in
                guard let chapterIndex = entry.chapterIndex, chapters.indices.contains(chapterIndex) else { return }
                showReaderChromeAfterChapterSelection = true
                selectedLocalChapterIndex = chapterIndex
                localNavigationRevision &+= 1
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: chapterIndex,
                    chapterTitle: entry.title,
                    totalChapters: chapters.count,
                    paragraphIndex: entry.paragraphIndex
                )
            },
            onSpeechFinished: {
                let nextIndex = safeIndex + 1
                guard chapters.indices.contains(nextIndex) else { return }
                autoplaySpeechAfterHandoff = true
                selectedLocalChapterIndex = nextIndex
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: nextIndex,
                    chapterTitle: chapters[nextIndex].title,
                    totalChapters: chapters.count
                )
            },
            autoplayAutoScrollOnAppear: autoplayAutoScrollAfterHandoff,
            onAutoScrollAutoplayConsumed: {
                autoplayAutoScrollAfterHandoff = false
            },
            onAutoScrollFinished: {
                guard chapters.indices.contains(safeIndex + 1) else { return }
                autoplayAutoScrollAfterHandoff = true
            },
            autoplaySpeechOnAppear: autoplaySpeechAfterHandoff,
            onSpeechAutoplayConsumed: {
                autoplaySpeechAfterHandoff = false
            },
            initialOverlayVisible: showReaderChromeAfterChapterSelection
        )
        .id("reader-\(book.id)-\(safeIndex)-\(localNavigationRevision)")
    }

    private func resumeReading() async {
        let activeBook = currentBook
        guard activeBook.localChapters == nil, activeBook.localContent == nil else { return }
        guard selectedChapter == nil, errorMessage == nil else { return }
        guard let source = appState.sourceStore.source(for: activeBook.sourceURL) else {
            errorMessage = "找不到书源：\(activeBook.sourceName)"
            return
        }

        let searchBook = SearchBook(
            name: activeBook.title,
            author: activeBook.author,
            coverUrl: activeBook.coverURL,
            bookUrl: activeBook.bookURL,
            sourceName: activeBook.sourceName,
            sourceUrl: activeBook.sourceURL,
            intro: activeBook.intro
        )

        let engine = appState.engine
        let detailResult = await AsyncTimeout.run(seconds: 12) {
            await engine.getBookDetail(source: source, book: searchBook)
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
                let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
                let target = loadedChapters.first(where: { $0.index == targetIndex })
                    ?? loadedChapters.first
                if let target {
                    appState.bookshelfStore.updateDetails(
                        bookID: activeBook.id,
                        latestChapterTitle: loadedDetail.latestChapter,
                        intro: loadedDetail.intro,
                        totalChapters: loadedChapters.count
                    )
                    selectedChapter = target
                } else {
                    errorMessage = "目录为空"
                }
            case .failure(let error):
                let cached = appState.chapterContentCacheStore.cachedChapters(
                    sourceURL: source.bookSourceUrl,
                    bookURL: activeBook.bookURL
                )
                let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
                if let target = cached.first(where: { $0.index == targetIndex }) ?? cached.first {
                    chapters = cached
                    selectedChapter = target
                    errorMessage = nil
                    appState.record(DiagnosticEvent(level: .info, stage: "reader.offline", sourceName: activeBook.sourceName, message: "目录网络失败，已切换到离线缓存", details: ["chapters": String(cached.count)]))
                } else {
                    errorMessage = "目录加载失败：\(error.displayMessage)"
                }
            }
        case .failure(let error):
            let cached = appState.chapterContentCacheStore.cachedChapters(
                sourceURL: source.bookSourceUrl,
                bookURL: activeBook.bookURL
            )
            let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
            if let target = cached.first(where: { $0.index == targetIndex }) ?? cached.first {
                chapters = cached
                selectedChapter = target
                errorMessage = nil
                appState.record(DiagnosticEvent(level: .info, stage: "reader.offline", sourceName: activeBook.sourceName, message: "详情网络失败，已切换到离线缓存", details: ["chapters": String(cached.count)]))
            } else {
                errorMessage = "详情加载失败：\(error.displayMessage)"
            }
        }
    }

    private var sourceSwitcherSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("搜索其他启用书源中的同名结果，选中后会保留当前书架项并切到新书源。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if sourceSwitchState.isLoading, sourceSwitchState.candidates.isEmpty {
                    ProgressView(sourceSwitchProgressTitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = sourceSwitchState.message {
                    EmptyStateCard(systemImage: "magnifyingglass", title: "换源结果", message: message)
                        .padding(.horizontal)
                } else {
                    List {
                        if sourceSwitchState.isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(sourceSwitchProgressTitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(sourceSwitchState.candidates) { candidate in
                            Button {
                                Task { await applySwitch(candidate) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.book.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(candidate.source.bookSourceName) · \(candidate.book.author ?? "作者未知")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(candidate.book.bookUrl)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                            }
                            .disabled(sourceSwitchState.isLoading)
                        }
                    }
                }
            }
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { showSourceSwitcher = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("搜索") {
                        sourceSwitchState = SourceSwitchState()
                        sourceSwitchSearchTrigger &+= 1
                    }
                    .disabled(sourceSwitchState.isLoading)
                }
            }
            .task(id: sourceSwitchSearchTrigger) {
                if sourceSwitchState.candidates.isEmpty, sourceSwitchState.message == nil {
                    await searchSwitchCandidates()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            // A dismissed sheet cancels its task. Clear a stale loading flag
            // so opening换源 again always starts a fresh search.
            if sourceSwitchState.isLoading {
                sourceSwitchState = SourceSwitchState()
            }
        }
    }

    private var sourceSwitchProgressTitle: String {
        guard sourceSwitchState.totalCount > 0 else { return "正在搜索可用换源" }
        return "正在搜索 \(sourceSwitchState.checkedCount)/\(sourceSwitchState.totalCount)"
    }

    private func searchSwitchCandidates() async {
        let activeBook = currentBook
        let enabledSources = Array(appState.sourceStore
            .sourceSwitchCandidates(for: activeBook.bookURL, excluding: activeBook.sourceURL)
            .prefix(40))
        sourceSwitchState = SourceSwitchState(isLoading: true, totalCount: enabledSources.count)
        var candidates: [SourceSwitchCandidate] = []
        let engine = appState.engine
        // Keep source switching responsive without creating a burst of 40
        // simultaneous network requests. Six requests per batch is enough to
        // hide a slow source while preserving cancellation and device limits.
        let batchSize = 6
        for start in stride(from: 0, to: enabledSources.count, by: batchSize) {
            guard !Task.isCancelled else { return }
            let end = min(start + batchSize, enabledSources.count)
            let batch = Array(enabledSources[start..<end])
            let batchCandidates = await withTaskGroup(of: SourceSwitchCandidate?.self, returning: [SourceSwitchCandidate].self) { group in
                for source in batch {
                    group.addTask {
                        let result = await AsyncTimeout.run(seconds: 10) {
                            await engine.searchBooks(source: source, keyword: activeBook.title, page: 1)
                        } ?? .failure(.network("Source switch search timed out"))
                        guard case .success(let books) = result else { return nil }
                        let match = books.first { candidate in
                            candidate.name.localizedCaseInsensitiveContains(activeBook.title)
                                || activeBook.title.localizedCaseInsensitiveContains(candidate.name)
                        } ?? books.first
                        guard let match else { return nil }
                        return SourceSwitchCandidate(source: source, book: match)
                    }
                }
                var results: [SourceSwitchCandidate] = []
                results.reserveCapacity(batch.count)
                for await candidate in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return results
                    }
                    if let candidate { results.append(candidate) }
                }
                return results
            }
            candidates.append(contentsOf: batchCandidates)
            candidates.sort { $0.source.bookSourceName < $1.source.bookSourceName }
            sourceSwitchState = SourceSwitchState(
                isLoading: true,
                candidates: candidates,
                checkedCount: end,
                totalCount: enabledSources.count
            )
        }
        guard !Task.isCancelled else { return }
        candidates.sort { $0.source.bookSourceName < $1.source.bookSourceName }
        sourceSwitchState = candidates.isEmpty
            ? SourceSwitchState(message: "没有搜索到可用换源结果。")
            : SourceSwitchState(candidates: candidates)
    }

    private func applySwitch(_ candidate: SourceSwitchCandidate) async {
        sourceSwitchState.isLoading = true
        let engine = appState.engine
        let detailResult = await AsyncTimeout.run(seconds: 12) {
            await engine.getBookDetail(source: candidate.source, book: candidate.book)
        } ?? .failure(.network("Detail load timed out"))
        switch detailResult {
        case .success(let detail):
            let chapterResult = await AsyncTimeout.run(seconds: 12) {
                await engine.getChapterList(source: candidate.source, book: detail)
            } ?? .failure(.network("Chapter list timed out"))
            switch chapterResult {
            case .success(let loadedChapters):
                appState.bookshelfStore.switchSource(
                    bookID: book.id,
                    to: candidate.book,
                    latestChapterTitle: detail.latestChapter ?? loadedChapters.last?.title,
                    intro: detail.intro,
                    totalChapters: loadedChapters.count
                )
                chapters = loadedChapters
                selectedChapter = loadedChapters.first
                errorMessage = nil
                showSourceSwitcher = false
                sourceSwitchState = SourceSwitchState()
            case .failure(let error):
                sourceSwitchState = SourceSwitchState(message: "目录加载失败：\(error.displayMessage)")
            }
        case .failure(let error):
            sourceSwitchState = SourceSwitchState(message: "详情加载失败：\(error.displayMessage)")
        }
    }
}

private struct SourceSwitchState: Sendable {
    var isLoading = false
    var candidates: [SourceSwitchCandidate] = []
    var message: String?
    var checkedCount = 0
    var totalCount = 0
}

private struct SourceSwitchCandidate: Identifiable, Sendable {
    var id: String { "\(source.bookSourceUrl)|\(book.bookUrl)" }
    let source: BookSource
    let book: SearchBook
}
