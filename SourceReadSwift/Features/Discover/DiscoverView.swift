import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DiscoverViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PodcastSectionTitle(
                        title: "发现",
                        subtitle: "原生 Swift 核心 · iOS Podcasts 风格"
                    )

                    searchHeader

                    if viewModel.isSearching {
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                            Text("正在搜索")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .podcastCard()
                    } else if let error = viewModel.errorMessage {
                        EmptyStateCard(
                            systemImage: "exclamationmark.triangle",
                            title: "搜索失败",
                            message: error
                        )
                    } else if viewModel.results.isEmpty {
                        EmptyStateCard(
                            systemImage: "magnifyingglass",
                            title: "搜索书名",
                            message: "Swift 原生核心会逐步接管搜索、目录和正文解析。"
                        )
                    } else {
                        resultsList
                    }
                }
                .padding(AppTheme.pagePadding)
            }
            .pageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                appState.sourceStore.seedForDevelopment()
                viewModel.bind(appState: appState)
            }
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索书名或作者", text: $viewModel.keyword)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }
                Button("搜索") {
                    Task { await viewModel.search() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(AppTheme.elevatedCard)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.capsuleRadius, style: .continuous))

            HStack {
                Text("已导入 \(appState.sourceStore.sources.count) 个源")
                Spacer()
                Text("命中 \(viewModel.hitSourceCount) 个源 · \(viewModel.results.count) 条")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .podcastCard()
    }

    private var resultsList: some View {
        LazyVStack(spacing: 14) {
            HStack {
                Text("搜索结果")
                    .font(.title2.bold())
                Spacer()
                Text("\(viewModel.results.count) 条")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.results) { book in
                NavigationLink {
                    BookDetailView(book: book)
                } label: {
                    SearchBookRow(book: book)
                        .podcastCard()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var keyword = "斗破苍穹"
    @Published var results: [SearchBook] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hitSourceCount = 0

    private weak var appState: AppState?

    func bind(appState: AppState) {
        self.appState = appState
    }

    func search() async {
        guard let appState else { return }
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        results = []
        hitSourceCount = 0
        defer { isSearching = false }

        let sources = appState.sourceStore.sources.filter(\.enabled)
        guard !sources.isEmpty else {
            errorMessage = "没有可用书源"
            return
        }

        var allBooks: [SearchBook] = []
        var hitSources = Set<String>()
        var failures: [String] = []

        for source in sources {
            switch await appState.engine.searchBooks(source: source, keyword: keyword, page: 1) {
            case .success(let books):
                if !books.isEmpty {
                    hitSources.insert(source.bookSourceUrl)
                    allBooks.append(contentsOf: books)
                }
            case .failure(let error):
                failures.append("\(source.bookSourceName): \(error.displayMessage)")
                appState.record(.init(
                    level: .warning,
                    stage: "search",
                    sourceName: source.bookSourceName,
                    message: error.displayMessage
                ))
            }
        }

        results = allBooks
        hitSourceCount = hitSources.count
        if allBooks.isEmpty {
            errorMessage = failures.prefix(5).joined(separator: "\n")
        }
    }
}
