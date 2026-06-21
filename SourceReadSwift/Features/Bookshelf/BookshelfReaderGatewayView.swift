import SwiftUI

struct BookshelfReaderGatewayView: View {
    @EnvironmentObject private var appState: AppState
    let book: BookshelfBook

    @State private var detail: BookDetail?
    @State private var chapters: [BookChapter] = []
    @State private var selectedChapter: BookChapter?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let selectedChapter {
                ChapterLoadingView(sourceUrl: book.sourceURL, chapter: selectedChapter, totalChapters: chapters.count)
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

    private func resumeReading() async {
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
