import SwiftSoup
import SwiftUI

struct RSSArticleReaderView: View {
    @EnvironmentObject private var appState: AppState
    let article: RSSArticlePreview

    @State private var paragraphs: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCachedContent = false
    @AppStorage("reader.fontSize") private var fontSize: Double = 19
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title)
                    .font(.system(size: fontSize + 5, weight: .bold, design: .serif))
                    .textSelection(.enabled)

                if let pubDate = article.pubDate {
                    Text(pubDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isLoading && paragraphs.isEmpty {
                    ProgressView("正在加载文章")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let errorMessage {
                    EmptyStateCard(systemImage: "exclamationmark.triangle", title: "文章加载失败", message: errorMessage)
                } else if paragraphs.isEmpty {
                    EmptyStateCard(systemImage: "doc.text", title: "暂无正文", message: "该文章没有可显示的正文内容。")
                } else {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.system(size: fontSize, design: .serif))
                            .lineSpacing(lineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                if showingCachedContent {
                    Text("显示已缓存正文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle("文章阅读")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let link = article.link, let url = URL(string: link) {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .task { await load() }
        .onAppear {
            appState.rssArticleStateStore.markRead(article)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    appState.rssArticleStateStore.toggleFavorite(article)
                } label: {
                    Image(systemName: appState.rssArticleStateStore.isFavorite(article) ? "star.fill" : "star")
                        .foregroundStyle(appState.rssArticleStateStore.isFavorite(article) ? .yellow : .primary)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        if let cachedHTML = appState.rssArticleContentCacheStore.contentHTML(for: article, maxAge: RSSFeedCacheStore.defaultMaxAge) {
            let cachedParagraphs = RSSArticleContentParser().parseParagraphs(from: cachedHTML)
            if !cachedParagraphs.isEmpty {
                paragraphs = cachedParagraphs
                showingCachedContent = true
            }
        }
        if let cached = appState.rssArticleContentCacheStore.paragraphs(for: article, maxAge: RSSFeedCacheStore.defaultMaxAge) {
            if paragraphs.isEmpty { paragraphs = cached }
            showingCachedContent = true
        }
        guard let link = article.link, let url = URL(string: link) else {
            if paragraphs.isEmpty {
                paragraphs = article.contentHTML.map { RSSArticleContentParser().parseParagraphs(from: $0) }
                    ?? article.description.map { RSSArticleContentParser().parseParagraphs(from: $0) }
                    ?? []
            }
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 SourceReadSwift", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let html = ResponseTextDecoder().decode(data: data, headers: [:])
            paragraphs = RSSArticleContentParser().parseParagraphs(from: html)
            if paragraphs.isEmpty, let description = article.description {
                paragraphs = RSSArticleContentParser().parseParagraphs(from: description)
            }
            if !paragraphs.isEmpty {
                appState.rssArticleContentCacheStore.save(paragraphs, for: article, contentHTML: article.contentHTML ?? html)
                showingCachedContent = false
            }
        } catch {
            if paragraphs.isEmpty {
                paragraphs = article.contentHTML.map { RSSArticleContentParser().parseParagraphs(from: $0) }
                    ?? article.description.map { RSSArticleContentParser().parseParagraphs(from: $0) }
                    ?? []
            }
            if paragraphs.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = nil
                showingCachedContent = true
            }
        }
    }
}
