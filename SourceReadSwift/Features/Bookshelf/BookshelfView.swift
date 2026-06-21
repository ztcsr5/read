import SwiftUI

struct BookshelfView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showImportUnavailable = false

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
                                showImportUnavailable = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("导入本地书籍")

                            Button {
                                showImportUnavailable = true
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

                    VStack(alignment: .leading, spacing: 8) {
                        PodcastChevronSectionHeader(title: "最新更新")
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

                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, AppTheme.pagePadding)
            }
            .refreshable {}
            .pageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .alert("本地导入正在恢复", isPresented: $showImportUnavailable) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("下一阶段会接回 Flutter 原版的本地文件导入、EPUB/TXT 解析和个人中心。")
            }
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
