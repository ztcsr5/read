import SwiftUI

struct RSSArticlesView: View {
    @EnvironmentObject private var appState: AppState
    let source: RSSSource

    @State private var articles: [RSSArticlePreview] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didLoadFeed = false
    @State private var showingStaleCache = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(source.sourceName)
                        .font(.headline)
                    Text(source.sourceUrl)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }

            if isLoading && articles.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("正在加载订阅")
                        Spacer()
                    }
                    .padding(.vertical, 30)
                }
            } else if let errorMessage, articles.isEmpty, !didLoadFeed {
                Section {
                    VStack(spacing: 12) {
                        EmptyStateCard(systemImage: "exclamationmark.triangle", title: "订阅加载失败", message: errorMessage)
                        Button {
                            Task { await loadArticles(force: true) }
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else if articles.isEmpty {
                Section {
                    EmptyStateCard(systemImage: "newspaper", title: "暂无文章", message: "该 RSS/Atom 源暂未解析出文章。")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } else {
                if showingStaleCache {
                    Section {
                        Label("当前显示离线缓存，刷新后可获取最新文章", systemImage: "externaldrive.badge.clock")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("文章") {
                    ForEach(articles) { article in
                        NavigationLink {
                            RSSArticleReaderView(article: article, articles: articles)
                        } label: {
                            RSSArticleRow(
                                article: article,
                                isRead: appState.rssArticleStateStore.isRead(article),
                                isFavorite: appState.rssArticleStateStore.isFavorite(article)
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("订阅文章")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadArticles(force: true) }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task {
            if let cached = appState.rssFeedCacheStore.articles(for: source.sourceUrl) {
                articles = cached
                showingStaleCache = appState.rssFeedCacheStore.isStale(sourceURL: source.sourceUrl)
            }
            await loadArticles(force: false)
        }
    }

    @MainActor
    private func loadArticles(force: Bool) async {
        guard force || !didLoadFeed else { return }
        isLoading = true
        errorMessage = nil
        didLoadFeed = false
        defer { isLoading = false }
        do {
            guard let url = URL(string: source.sourceUrl) else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 SourceReadSwift", forHTTPHeaderField: "User-Agent")
            request.setValue("application/rss+xml,application/atom+xml,application/xml,text/xml,text/plain,*/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let text = ResponseTextDecoder().decode(data: data, headers: [:])
            let parsed = RSSFeedParser().parseArticles(from: text, sourceURL: source.sourceUrl)
            didLoadFeed = true
            if parsed.isEmpty {
                errorMessage = "已加载响应，但没有识别到 RSS/Atom 文章。"
            }
            articles = Array(parsed.prefix(100))
            appState.rssFeedCacheStore.save(articles, sourceURL: source.sourceUrl)
            showingStaleCache = false
        } catch {
            if articles.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "网络不可用，正在显示离线缓存文章"
                showingStaleCache = true
            }
        }
    }
}

private struct RSSArticleRow: View {
    let article: RSSArticlePreview
    let isRead: Bool
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                if let imageURL = article.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(article.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            if let pubDate = article.pubDate {
                Text(pubDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let description = article.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if article.link != nil {
                Label("打开文章阅读", systemImage: "book")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            if isRead {
                Text("已读")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
