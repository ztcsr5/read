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

                    matchModePicker
                    searchHeader
                    content
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

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching && viewModel.results.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("正在搜索")
                    .font(.headline)
                Text("已检测 \(viewModel.checkedSourceCount) 个源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .podcastCard()
        } else if let error = viewModel.errorMessage, viewModel.results.isEmpty {
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
                Text("已检 \(viewModel.checkedSourceCount) · 命中 \(viewModel.hitSourceCount) · \(viewModel.results.count) 条")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .podcastCard()
    }

    private var matchModePicker: some View {
        Picker("搜索模式", selection: $viewModel.matchMode) {
            ForEach(SearchMatchMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .background(AppTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.capsuleRadius, style: .continuous))
    }

    private var resultsList: some View {
        LazyVStack(spacing: 14) {
            HStack {
                Text("搜索结果")
                    .font(.title2.bold())
                Spacer()
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
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
    @Published var matchMode: SearchMatchMode = .fuzzy
    @Published var results: [SearchBook] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hitSourceCount = 0
    @Published var checkedSourceCount = 0

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
        checkedSourceCount = 0
        defer { isSearching = false }

        let sources = appState.sourceStore.sources.filter(\.enabled)
        guard !sources.isEmpty else {
            errorMessage = "没有可用书源"
            return
        }

        let engine = appState.engine
        var allBooks: [SearchBook] = []
        var hitSources = Set<String>()
        var failures: [String] = []

        for batch in sources.chunked(into: 12) {
            await withTaskGroup(of: (BookSource, Result<[SearchBook], SourceEngineError>).self) { group in
                for source in batch {
                    group.addTask {
                        let result = await engine.searchBooks(source: source, keyword: keyword, page: 1)
                        return (source, result)
                    }
                }

                for await (source, result) in group {
                    checkedSourceCount += 1
                    switch result {
                    case .success(let books):
                        if !books.isEmpty {
                            hitSources.insert(source.bookSourceUrl)
                            allBooks.append(contentsOf: books)
                            results = filtered(allBooks, keyword: keyword)
                            hitSourceCount = hitSources.count
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
            }
        }

        results = filtered(allBooks, keyword: keyword)
        hitSourceCount = hitSources.count
        if results.isEmpty {
            errorMessage = failures.prefix(5).joined(separator: "\n")
        }
    }

    private func filtered(_ books: [SearchBook], keyword: String) -> [SearchBook] {
        guard matchMode == .exact else { return books }
        return books.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || ($0.author?.localizedCaseInsensitiveContains(keyword) ?? false)
        }
    }
}

enum SearchMatchMode: String, CaseIterable, Identifiable {
    case fuzzy
    case exact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fuzzy: return "模糊"
        case .exact: return "精准"
        }
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
