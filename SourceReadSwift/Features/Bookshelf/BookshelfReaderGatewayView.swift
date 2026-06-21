import SwiftUI

struct BookshelfReaderGatewayView: View {
    @EnvironmentObject private var appState: AppState
    let book: BookshelfBook

    @State private var detail: BookDetail?
    @State private var chapters: [BookChapter] = []
    @State private var selectedChapter: BookChapter?
    @State private var selectedLocalChapterIndex: Int?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !localBookChapters.isEmpty {
                localReader
            } else if let localContent = book.localContent {
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
            } else if let selectedChapter {
                ChapterLoadingView(
                    sourceUrl: book.sourceURL,
                    chapter: selectedChapter,
                    totalChapters: chapters.count,
                    chapters: chapters
                )
            } else if let errorMessage {
                EmptyStateCard(systemImage: "xmark.octagon", title: "阅读恢复失败", message: errorMessage)
                    .padding(AppTheme.pagePadding)
                    .pageBackground()
            } else {
                ProgressView("正在恢复阅读进度")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pageBackground()
            }
        }
        .task {
            await resumeReading()
        }
    }

    private var localBookChapters: [LocalTextChapter] {
        book.localChapters ?? []
    }

    private var localReader: some View {
        let chapters = localBookChapters
        let requestedIndex = selectedLocalChapterIndex ?? book.currentChapterIndex
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
        guard book.localChapters == nil, book.localContent == nil else { return }
        guard selectedChapter == nil, errorMessage == nil else { return }
        guard let source = appState.sourceStore.source(for: book.sourceURL) else {
            errorMessage = "找不到书源：\(book.sourceName)"
            return
        }

        let searchBook = SearchBook(
            name: book.title,
            author: book.author,
            coverUrl: book.coverURL,
            bookUrl: book.bookURL,
            sourceName: book.sourceName,
            sourceUrl: book.sourceURL,
            intro: book.intro
        )

        switch await appState.engine.getBookDetail(source: source, book: searchBook) {
        case .success(let loadedDetail):
            detail = loadedDetail
            switch await appState.engine.getChapterList(source: source, book: loadedDetail) {
            case .success(let loadedChapters):
                chapters = loadedChapters
                let target = loadedChapters.first(where: { $0.index == book.currentChapterIndex })
                    ?? loadedChapters.first
                if let target {
                    appState.bookshelfStore.updateDetails(
                        bookID: book.id,
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
}
