import SwiftUI

struct BookshelfReaderGatewayView: View {
    @EnvironmentObject private var appState: AppState
    let book: BookshelfBook

    @State private var detail: BookDetail?
    @State private var chapters: [BookChapter] = []
    @State private var selectedChapter: BookChapter?
    @State private var selectedLocalChapterIndex: Int?
    @State private var errorMessage: String?
    @State private var showSourceSwitcher = false
    @State private var sourceSwitchState = SourceSwitchState()

    private var currentBook: BookshelfBook {
        appState.bookshelfStore.book(id: book.id) ?? book
    }

    var body: some View {
        gatewayContent
        .task {
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
        let requestedIndex = selectedLocalChapterIndex ?? currentBook.currentChapterIndex
        let safeIndex = min(max(requestedIndex, 0), max(chapters.count - 1, 0))
        let localChapter = chapters[safeIndex]
        let bookChapters = chapters.map {
            BookChapter(
                title: $0.title,
                url: "\(book.bookURL)#\($0.index)",
                bookUrl: book.bookURL,
                index: $0.index,
                isVip: false
            )
        }
        return ReaderView(
            bookID: book.id,
            content: ChapterContent(
                chapter: bookChapters[safeIndex],
                title: localChapter.title,
                paragraphs: localChapter.paragraphs,
                nextContentUrl: nil
            ),
            chapterIndex: safeIndex,
            totalChapters: chapters.count,
            chapters: bookChapters,
            onSelectChapter: { chapter in
                selectedLocalChapterIndex = chapter.index
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: chapter.index,
                    chapterTitle: chapter.title,
                    totalChapters: chapters.count
                )
            }
        )
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

        switch await appState.engine.getBookDetail(source: source, book: searchBook) {
        case .success(let loadedDetail):
            detail = loadedDetail
            switch await appState.engine.getChapterList(source: source, book: loadedDetail) {
            case .success(let loadedChapters):
                chapters = loadedChapters
                let target = loadedChapters.first(where: { $0.index == activeBook.currentChapterIndex })
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
                errorMessage = "目录加载失败：\(error.displayMessage)"
            }
        case .failure(let error):
            errorMessage = "详情加载失败：\(error.displayMessage)"
        }
    }

    private var sourceSwitcherSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("搜索其他启用书源中的同名结果，选中后会保留当前书架项并切到新书源。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if sourceSwitchState.isLoading {
                    ProgressView("正在搜索可用换源")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = sourceSwitchState.message {
                    EmptyStateCard(systemImage: "magnifyingglass", title: "换源结果", message: message)
                        .padding(.horizontal)
                } else {
                    List(sourceSwitchState.candidates) { candidate in
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
                        Task { await searchSwitchCandidates() }
                    }
                    .disabled(sourceSwitchState.isLoading)
                }
            }
            .task {
                if sourceSwitchState.candidates.isEmpty, sourceSwitchState.message == nil {
                    await searchSwitchCandidates()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func searchSwitchCandidates() async {
        sourceSwitchState = SourceSwitchState(isLoading: true)
        let activeBook = currentBook
        let enabledSources = appState.sourceStore.sources
            .filter { $0.enabled && $0.bookSourceUrl != activeBook.sourceURL && $0.searchUrl != nil }
            .prefix(40)
        var candidates: [SourceSwitchCandidate] = []
        for source in enabledSources {
            let result = await appState.engine.searchBooks(source: source, keyword: activeBook.title, page: 1)
            guard case .success(let books) = result else { continue }
            let match = books.first { candidate in
                candidate.name.localizedCaseInsensitiveContains(activeBook.title)
                    || activeBook.title.localizedCaseInsensitiveContains(candidate.name)
            } ?? books.first
            if let match {
                candidates.append(SourceSwitchCandidate(source: source, book: match))
            }
        }
        candidates.sort { $0.source.bookSourceName < $1.source.bookSourceName }
        sourceSwitchState = candidates.isEmpty
            ? SourceSwitchState(message: "没有搜索到可用换源结果。")
            : SourceSwitchState(candidates: candidates)
    }

    private func applySwitch(_ candidate: SourceSwitchCandidate) async {
        sourceSwitchState.isLoading = true
        switch await appState.engine.getBookDetail(source: candidate.source, book: candidate.book) {
        case .success(let detail):
            switch await appState.engine.getChapterList(source: candidate.source, book: detail) {
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

private struct SourceSwitchState {
    var isLoading = false
    var candidates: [SourceSwitchCandidate] = []
    var message: String?
}

private struct SourceSwitchCandidate: Identifiable {
    var id: String { "\(source.bookSourceUrl)|\(book.bookUrl)" }
    let source: BookSource
    let book: SearchBook
}
