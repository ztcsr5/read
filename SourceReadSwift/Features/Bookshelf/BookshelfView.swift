import SwiftUI
import UniformTypeIdentifiers

struct BookshelfView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showFileImporter = false
    @State private var importMessage: String?
    @State private var isRefreshingBooks = false

    private var recentBooks: [BookshelfBook] {
        appState.bookshelfStore.recentBooks
    }

    private var updatedBooks: [BookshelfBook] {
        appState.bookshelfStore.updatedBooks
    }

    private var allBooks: [BookshelfBook] {
        appState.bookshelfStore.books
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    PodcastLargeTitleBar(title: "主页") {
                        HStack(spacing: 18) {
                            Button {
                                showFileImporter = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("导入本地书籍")

                            NavigationLink {
                                ReaderProfileView()
                            } label: {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 38, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("个人中心")
                        }
                    }
                    .padding(.top, 18)

                    readingSection
                    updatesSection
                    shelfSection
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, AppTheme.pagePadding)
            }
            .refreshable {
                await refreshBookshelf()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.plainText, .text, .epub, .item],
                allowsMultipleSelection: false,
                onCompletion: importLocalBook
            )
            .pageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .alert("本地导入", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PodcastChevronSectionHeader(title: "正在阅读")
            if recentBooks.isEmpty {
                CenterTextEmptyState("暂无阅读记录", minHeight: 240)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(recentBooks.prefix(8)) { book in
                            heroCard(book)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PodcastChevronSectionHeader(title: "最新更新")
                if isRefreshingBooks {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if updatedBooks.isEmpty {
                CenterTextEmptyState("暂无更新书籍", minHeight: 220)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(updatedBooks) { book in
                        updateRow(book)
                    }
                }
            }
        }
    }

    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PodcastChevronSectionHeader(title: "书架")
            if allBooks.isEmpty {
                CenterTextEmptyState("书架还是空的", minHeight: 140)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(allBooks) { book in
                        bookshelfRow(book)
                    }
                }
            }
        }
    }

    private func importLocalBook(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let parsed: LocalTextBook
            if url.pathExtension.localizedCaseInsensitiveCompare("epub") == .orderedSame {
                parsed = try LocalEPUBBookParser().parse(fileURL: url)
            } else {
                let data = try Data(contentsOf: url)
                parsed = LocalTextBookParser().parse(data: data, fileName: url.lastPathComponent)
            }
            appState.bookshelfStore.addLocalTextBook(parsed)
            importMessage = "已导入《\(parsed.title)》，共 \(parsed.chapters.count) 章、\(parsed.paragraphs.count) 段。"
        } catch {
            importMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func refreshBookshelf() async {
        guard !isRefreshingBooks else { return }
        isRefreshingBooks = true
        defer { isRefreshingBooks = false }

        var refreshed = 0
        var failed = 0
        let books = appState.bookshelfStore.books
        for book in books where !book.sourceURL.hasPrefix("local://") {
            guard let source = appState.sourceStore.source(for: book.sourceURL), source.enabled else {
                failed += 1
                continue
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
            case .success(let detail):
                switch await appState.engine.getChapterList(source: source, book: detail) {
                case .success(let chapters):
                    appState.bookshelfStore.updateDetails(
                        bookID: book.id,
                        latestChapterTitle: detail.latestChapter ?? chapters.last?.title,
                        intro: detail.intro,
                        totalChapters: chapters.count
                    )
                    refreshed += 1
                case .failure(let error):
                    appState.bookshelfStore.markRefreshFailure(bookID: book.id, message: error.displayMessage)
                    failed += 1
                }
            case .failure(let error):
                appState.bookshelfStore.markRefreshFailure(bookID: book.id, message: error.displayMessage)
                failed += 1
            }
        }

        if refreshed > 0 || failed > 0 {
            importMessage = "刷新完成：成功 \(refreshed)，失败 \(failed)。"
        } else {
            importMessage = "没有需要刷新的在线书籍。"
        }
    }

    private func heroCard(_ book: BookshelfBook) -> some View {
        NavigationLink {
            BookshelfReaderGatewayView(book: book)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                AsyncBookCover(urlString: book.coverURL, width: 72, height: 96)

                Text("已读 \(Int(book.readingProgress * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                HStack {
                    Label("继续阅读", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                    Spacer()
                }
            }
            .padding(18)
            .frame(width: 295, height: 250, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.21, blue: 0.34), Color(red: 0.27, green: 0.25, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("从书架删除", role: .destructive) {
                appState.bookshelfStore.remove(bookID: book.id)
            }
        }
    }

    private func updateRow(_ book: BookshelfBook) -> some View {
        NavigationLink {
            BookshelfReaderGatewayView(book: book)
        } label: {
            HStack(spacing: 14) {
                AsyncBookCover(urlString: book.coverURL, width: 70, height: 100)

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let latest = book.latestChapterTitle {
                        Text("更新到 \(latest)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func bookshelfRow(_ book: BookshelfBook) -> some View {
        NavigationLink {
            BookshelfReaderGatewayView(book: book)
        } label: {
            HStack(spacing: 14) {
                AsyncBookCover(urlString: book.coverURL, width: 52, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let current = book.currentChapterTitle {
                        Text("读到：\(current)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("从书架删除", role: .destructive) {
                appState.bookshelfStore.remove(bookID: book.id)
            }
        }
    }
}

private extension UTType {
    static let epub = UTType(filenameExtension: "epub") ?? .data
}

private struct ReaderProfileView: View {
    @EnvironmentObject private var appState: AppState

    private var totalBooks: Int {
        appState.bookshelfStore.books.count
    }

    private var localBooks: Int {
        appState.bookshelfStore.books.filter { $0.sourceURL.hasPrefix("local://") }.count
    }

    private var bookmarkedBooks: Int {
        appState.bookshelfStore.books.filter { !($0.bookmarks ?? []).isEmpty }.count
    }

    private var readBooks: Int {
        appState.bookshelfStore.books.filter { $0.lastReadAt != nil }.count
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本地阅读")
                            .font(.headline)
                        Text("数据仅保存在当前设备")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("统计") {
                profileMetric("书架书籍", value: totalBooks, icon: "books.vertical")
                profileMetric("本地导入", value: localBooks, icon: "doc.text")
                profileMetric("已阅读", value: readBooks, icon: "clock")
                profileMetric("有书签", value: bookmarkedBooks, icon: "bookmark")
            }

            Section("数据") {
                NavigationLink {
                    ReadingHistoryView()
                } label: {
                    Label("阅读历史", systemImage: "clock.arrow.circlepath")
                }

                NavigationLink {
                    SourceManagerView()
                } label: {
                    Label("书源管理", systemImage: "square.stack.3d.up")
                }
            }
        }
        .navigationTitle("个人中心")
    }

    private func profileMetric(_ title: String, value: Int, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
        }
    }
}

private struct AsyncBookCover: View {
    let urlString: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay {
                Image(systemName: "book.closed")
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}
