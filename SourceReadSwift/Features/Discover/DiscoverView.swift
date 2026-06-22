import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var selectedTab: DiscoverTab = .books

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("发现")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 18)

                    Picker("发现分类", selection: $selectedTab) {
                        ForEach(DiscoverTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case .books:
                        bookSearchTab
                    case .subscriptions:
                        subscriptionTab
                    case .sourceWriting:
                        sourceWritingTab
                    }

                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, AppTheme.pagePadding)
            }
            .pageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.bind(appState: appState)
            }
        }
    }

    private var bookSearchTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 14) {
                searchField
                webModeButton
                sourceManagerCard
                matchModePicker
            }

            Text("搜索结果")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            content
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("搜索书名或作者", text: $viewModel.keyword)
                .font(.system(size: 16, weight: .semibold))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    Task { await viewModel.search() }
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var webModeButton: some View {
        NavigationLink {
            WebNovelModeView()
        } label: {
            Label("智能网页小说模式", systemImage: "globe")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AppTheme.softBlue)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sourceManagerCard: some View {
        NavigationLink {
            SourceManagerView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "cube")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("书源管理")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text("导入、测试、验证和管理网络书源")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var matchModePicker: some View {
        HStack {
            Spacer()
            Picker("搜索模式", selection: $viewModel.matchMode) {
                ForEach(SearchMatchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
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
                Text("已检测 \(viewModel.checkedSourceCount)/\(appState.sourceStore.sources.count) 个源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("取消搜索") {
                    viewModel.cancelSearch()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        } else if let error = viewModel.errorMessage, viewModel.results.isEmpty {
            EmptyStateCard(systemImage: "exclamationmark.triangle", title: "搜索失败", message: error)
        } else if viewModel.results.isEmpty {
            Text("输入书名后，会从启用的小说书源里搜索")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 250)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        LazyVStack(spacing: 14) {
            HStack {
                Text("已检测 \(viewModel.checkedSourceCount)/\(appState.sourceStore.sources.count) 个源 · 命中 \(viewModel.hitSourceCount) 个源 · 结果 \(viewModel.results.count) 条")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ForEach(viewModel.results) { book in
                NavigationLink {
                    BookDetailView(book: book)
                } label: {
                    SearchBookRow(
                        book: book,
                        onAdd: {
                            appState.bookshelfStore.addOrUpdate(book)
                        },
                        isInBookshelf: appState.bookshelfStore.contains(book)
                    )
                        .podcastCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subscriptionTab: some View {
        VStack(spacing: 18) {
            if appState.sourceStore.rssSources.isEmpty {
                EmptyStateCard(
                    systemImage: "newspaper",
                    title: "暂无订阅源",
                    message: "RSS/订阅源会在书源管理中统一导入和维护。"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(appState.sourceStore.rssSources) { source in
                        NavigationLink {
                            RSSArticlesView(source: source)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "newspaper")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.sourceName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(source.sourceUrl)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(source.enabled ? "启用" : "停用")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(source.enabled ? .green : .secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .podcastCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            NavigationLink {
                SourceManagerView()
            } label: {
                Text("前往管理")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sourceWritingTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            NavigationLink {
                SourceWritingView(server: appState.sourceWritingServer)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "globe")
                        .font(.system(size: 28, weight: .semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Web 写源")
                            .font(.system(size: 20, weight: .bold))
                        Text("用网页信息辅助整理、导入和验证书源规则")
                            .font(.system(size: 13, weight: .regular))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WebNovelModeView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("智能网页小说模式")
                        .font(.title2.bold())
                    Text("当前 Swift 版本优先走书源引擎。网页模式用于辅助发现站点、复制 URL、整理规则，并通过书源管理导入验证。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("建议流程") {
                Label("在 Safari 或站点页面找到小说搜索/目录/正文页", systemImage: "safari")
                Label("复制地址或分享文本到书源管理", systemImage: "doc.on.clipboard")
                Label("用书源测试验证搜索、详情、目录、正文", systemImage: "checkmark.seal")
            }

            Section {
                NavigationLink {
                    SourceManagerView()
                } label: {
                    Label("打开书源管理", systemImage: "square.stack.3d.up")
                }
            }
        }
        .navigationTitle("网页模式")
    }
}

private enum DiscoverTab: String, CaseIterable, Identifiable {
    case books
    case subscriptions
    case sourceWriting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .books: return "找书"
        case .subscriptions: return "订阅"
        case .sourceWriting: return "写源"
        }
    }
}

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var keyword = ""
    @Published var matchMode: SearchMatchMode = .fuzzy
    @Published var results: [SearchBook] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hitSourceCount = 0
    @Published var checkedSourceCount = 0
    @Published var totalResultCount = 0

    private weak var appState: AppState?
    private var activeSearchID: UUID?

    func bind(appState: AppState) {
        self.appState = appState
    }

    func cancelSearch() {
        activeSearchID = nil
        isSearching = false
    }

    func search() async {
        guard let appState else { return }
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        errorMessage = nil
        results = []
        totalResultCount = 0
        hitSourceCount = 0
        checkedSourceCount = 0
        defer {
            if activeSearchID == searchID {
                isSearching = false
            }
        }

        let sources = appState.sourceStore.sources.filter(\.enabled)
        guard !sources.isEmpty else {
            errorMessage = "没有可用书源，请先到书源管理导入书源。"
            return
        }

        let engine = appState.engine
        var allBooks: [SearchBook] = []
        var hitSources = Set<String>()
        var failures: [String] = []

        for batch in sources.chunked(into: 12) {
            guard activeSearchID == searchID else { return }
            await withTaskGroup(of: (BookSource, Result<[SearchBook], SourceEngineError>).self) { group in
                for source in batch {
                    group.addTask {
                        let result = await engine.searchBooks(source: source, keyword: keyword, page: 1)
                        return (source, result)
                    }
                }

                for await (source, result) in group {
                    guard activeSearchID == searchID else { continue }
                    checkedSourceCount += 1
                    switch result {
                    case .success(let books):
                        if !books.isEmpty {
                            hitSources.insert(source.bookSourceUrl)
                            allBooks.append(contentsOf: books)
                            totalResultCount = allBooks.count
                            hitSourceCount = hitSources.count
                        }
                    case .failure(let error):
                        failures.append("\(source.bookSourceName): \(error.displayMessage)")
                    }
                    if checkedSourceCount % 6 == 0 || !allBooks.isEmpty && checkedSourceCount % 3 == 0 {
                        results = filtered(allBooks, keyword: keyword)
                        totalResultCount = allBooks.count
                    }
                }
            }
            results = filtered(allBooks, keyword: keyword)
            totalResultCount = allBooks.count
            hitSourceCount = hitSources.count
        }

        guard activeSearchID == searchID else { return }
        totalResultCount = allBooks.count
        results = filtered(allBooks, keyword: keyword)
        hitSourceCount = hitSources.count
        if results.isEmpty {
            errorMessage = failures.isEmpty ? "没有搜索结果，请检查关键词或书源规则。" : failures.prefix(8).joined(separator: "\n")
        }
    }

    private func filtered(_ books: [SearchBook], keyword: String) -> [SearchBook] {
        guard matchMode == .exact else { return books }
        return books.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || ($0.author?.localizedCaseInsensitiveContains(keyword) ?? false)
                || $0.sourceName.localizedCaseInsensitiveContains(keyword)
                || $0.bookUrl.localizedCaseInsensitiveContains(keyword)
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
