import SwiftUI
import UniformTypeIdentifiers

struct BookshelfView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFileImporter = false
    @State private var importMessage: String?
    @State private var isRefreshingBooks = false
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue

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
                LazyVStack(alignment: .leading, spacing: 30) {
                    PodcastLargeTitleBar(title: "主页") {
                        HStack(spacing: 18) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showFileImporter = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 46, height: 46)
                                    .glassCircle()
                            }
                            .buttonStyle(PressableScaleButtonStyle())
                            .accessibilityLabel("导入本地书籍")
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
            .background(bookshelfBackdrop)
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
            .sheet(isPresented: $showFileImporter) {
                UniversalDocumentPicker(
                    contentTypes: [
                        .plainText,
                        .text,
                        .data,
                        .content,
                        .item,
                        UTType(filenameExtension: "txt") ?? .plainText,
                        UTType(filenameExtension: "text") ?? .text,
                        UTType(filenameExtension: "epub") ?? UTType(importedAs: "org.idpf.epub-container")
                    ],
                    onPick: { urls in
                        showFileImporter = false
                        importLocalBook(.success(urls))
                    },
                    onCancel: { showFileImporter = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    private var bookshelfBackdrop: some View {
        _ = themeModeRawValue
        return ZStack {
            AppTheme.background
            LinearGradient(
                colors: [
                    AppTheme.accent.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.03)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.45),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            collectionHeader(title: "正在阅读", books: recentBooks)
            if recentBooks.isEmpty {
                emptyImportCard
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(recentBooks.prefix(8)) { book in
                            heroCard(book)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                collectionHeader(title: "最新更新", books: updatedBooks)
                if isRefreshingBooks {
                    ProgressView()
                        .controlSize(.small)
                } else if !allBooks.isEmpty {
                    Button {
                        Task { await refreshBookshelf() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("检查书籍更新")
                }
            }
            if updatedBooks.isEmpty {
                compactEmptyState(
                    icon: "sparkles",
                    title: "暂无更新",
                    message: allBooks.isEmpty ? "导入书籍后，更新会显示在这里" : "点击刷新按钮检查书籍更新"
                )
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
            shelfHeader
            if allBooks.isEmpty {
                compactEmptyState(icon: "books.vertical", title: "书架还是空的", message: "支持 TXT、EPUB 与在线书源书籍")
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(allBooks) { book in
                        bookshelfRow(book)
                    }
                }
            }
        }
    }

    private var shelfHeader: some View {
        NavigationLink {
            BookshelfCollectionView(title: "书架", books: allBooks)
        } label: {
            HStack(spacing: 7) {
                Text("书架")
                    .font(.system(size: 22, weight: .bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func collectionHeader(title: String, books: [BookshelfBook]) -> some View {
        if books.isEmpty {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        } else {
            NavigationLink {
                BookshelfCollectionView(title: title, books: books)
            } label: {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyImportCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showFileImporter = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                    Image(systemName: "book.badge.plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text("导入第一本书")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("从文件中选择 TXT 或 EPUB，立即开始阅读")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .glassPanel(cornerRadius: 22, material: .thinMaterial, shadowOpacity: 0.08)
        }
        .buttonStyle(.plain)
    }

    private func compactEmptyState(icon: String, title: String, message: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassPanel(cornerRadius: 18, material: .thinMaterial, shadowOpacity: 0.07)
    }

    private func importLocalBook(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                importMessage = "导入失败：没有选择文件。"
                return
            }
            let localURL = try PickedDocumentAccess.copiedURL(from: url)
            let parsed: LocalTextBook
            if localURL.pathExtension.localizedCaseInsensitiveCompare("epub") == .orderedSame {
                parsed = try LocalEPUBBookParser().parse(fileURL: localURL)
            } else {
                let data = try Data(contentsOf: localURL)
                parsed = LocalTextBookParser().parse(data: data, fileName: localURL.lastPathComponent)
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
        let engine = appState.engine
        let candidates: [BookshelfRefreshCandidate] = books.compactMap { book in
            guard !book.sourceURL.hasPrefix("local://") else { return nil }
            guard let source = appState.sourceStore.source(for: book.sourceURL), source.enabled else {
                failed += 1
                return nil
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
            return BookshelfRefreshCandidate(bookID: book.id, source: source, book: searchBook)
        }

        for batch in candidates.chunked(into: 4) {
            await withTaskGroup(of: BookshelfRefreshResult.self) { group in
                for candidate in batch {
                    group.addTask {
                        switch await engine.getBookDetail(source: candidate.source, book: candidate.book) {
                        case .success(let detail):
                            switch await engine.getChapterList(source: candidate.source, book: detail) {
                            case .success(let chapters):
                                return .success(
                                    bookID: candidate.bookID,
                                    latestChapterTitle: detail.latestChapter ?? chapters.last?.title,
                                    intro: detail.intro,
                                    totalChapters: chapters.count
                                )
                            case .failure(let error):
                                return .failure(bookID: candidate.bookID, message: error.displayMessage)
                            }
                        case .failure(let error):
                            return .failure(bookID: candidate.bookID, message: error.displayMessage)
                        }
                    }
                }

                for await result in group {
                    switch result {
                    case .success(let bookID, let latestChapterTitle, let intro, let totalChapters):
                        appState.bookshelfStore.updateDetails(
                            bookID: bookID,
                            latestChapterTitle: latestChapterTitle,
                            intro: intro,
                            totalChapters: totalChapters
                        )
                        refreshed += 1
                    case .failure(let bookID, let message):
                        appState.bookshelfStore.markRefreshFailure(bookID: bookID, message: message)
                        failed += 1
                    }
                }
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
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    AsyncBookCover(urlString: book.coverURL, width: 78, height: 108)
                        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 10)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(book.lastReadAt == nil ? "待开始" : "已读 \(Int(book.readingProgress * 100))%")
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 14)

                HStack {
                    Label("继续阅读", systemImage: "book.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(20)
            .frame(width: 312, height: 246, alignment: .topLeading)
            .background(
                heroGradient(for: book)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.13), radius: 22, x: 0, y: 14)
            .padding(.vertical, 6)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .contextMenu {
            Button("从书架删除", role: .destructive) {
                appState.bookshelfStore.remove(bookID: book.id)
            }
        }
    }

    private func heroGradient(for book: BookshelfBook) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.10, green: 0.16, blue: 0.09), Color(red: 0.18, green: 0.24, blue: 0.14)],
            [Color(red: 0.18, green: 0.14, blue: 0.12), Color(red: 0.30, green: 0.25, blue: 0.21)],
            [Color(red: 0.16, green: 0.14, blue: 0.28), Color(red: 0.28, green: 0.22, blue: 0.44)]
        ]
        let index = Int(book.id.hashValue.magnitude % UInt(palettes.count))
        return LinearGradient(colors: palettes[index], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            .padding(12)
            .glassPanel(cornerRadius: 18, material: .thinMaterial, shadowOpacity: 0.08)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            appState.bookshelfStore.markUpdatesSeen(bookID: book.id)
        })
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
            .glassPanel(cornerRadius: 16, material: .thinMaterial, shadowOpacity: 0.06)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .contextMenu {
            Button("从书架删除", role: .destructive) {
                appState.bookshelfStore.remove(bookID: book.id)
            }
        }
    }
}

private struct BookshelfRefreshCandidate: Sendable {
    let bookID: String
    let source: BookSource
    let book: SearchBook
}

private enum BookshelfRefreshResult: Sendable {
    case success(bookID: String, latestChapterTitle: String?, intro: String?, totalChapters: Int)
    case failure(bookID: String, message: String)
}

private struct BookshelfCollectionView: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let books: [BookshelfBook]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(books) { book in
                    NavigationLink {
                        BookshelfReaderGatewayView(book: book)
                    } label: {
                        HStack(spacing: 14) {
                            AsyncBookCover(urlString: book.coverURL, width: 58, height: 82)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(book.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(book.author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(book.currentChapterTitle ?? book.latestChapterTitle ?? "尚未开始阅读")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressableScaleButtonStyle())
                    .simultaneousGesture(TapGesture().onEnded {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        appState.bookshelfStore.markUpdatesSeen(bookID: book.id)
                    })
                    .contextMenu {
                        Button("从书架删除", role: .destructive) {
                            appState.bookshelfStore.remove(bookID: book.id)
                        }
                    }
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private struct PressableScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.78), value: configuration.isPressed)
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
