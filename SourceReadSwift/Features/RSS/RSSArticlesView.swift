import SwiftUI

struct RSSArticlesView: View {
    let source: RSSSource

    @State private var articles: [RSSArticlePreview] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

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
            } else if let errorMessage, articles.isEmpty {
                Section {
                    EmptyStateCard(systemImage: "exclamationmark.triangle", title: "订阅加载失败", message: errorMessage)
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
                Section("文章") {
                    ForEach(articles) { article in
                        RSSArticleRow(article: article)
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
            await loadArticles(force: false)
        }
    }

    @MainActor
    private func loadArticles(force: Bool) async {
        guard force || articles.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let url = URL(string: source.sourceUrl) else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 SourceReadSwift", forHTTPHeaderField: "User-Agent")
            request.setValue("application/rss+xml,application/atom+xml,application/xml,text/xml,text/plain,*/*", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let text = ResponseTextDecoder().decode(data: data, headers: [:])
            let parsed = RSSFeedParser().parseArticles(from: text)
            if parsed.isEmpty {
                errorMessage = "已加载响应，但没有识别到 RSS/Atom 文章。"
            }
            articles = Array(parsed.prefix(100))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RSSArticleRow: View {
    let article: RSSArticlePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(article.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

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

            if let link = article.link, let url = URL(string: link) {
                Link("打开原文", destination: url)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
    }
}
