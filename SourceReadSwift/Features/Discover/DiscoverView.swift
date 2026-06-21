import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var selectedTab: DiscoverTab = .books
    @State private var showWebModeNotice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("发现")
                        .font(.system(size: 44, weight: .bold))
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
            .alert("智能网页小说模式", isPresented: $showWebModeNotice) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("这个入口会在后续阶段接回 Flutter 版的内置网页搜索和写源流程。")
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
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            content
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("搜索书名或作者", text: $viewModel.keyword)
                .font(.system(size: 24, weight: .semibold))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    Task { await viewModel.search() }
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var webModeButton: some View {
        Button {
            showWebModeNotice = true
        } label: {
            Label("智能网页小说模式", systemImage: "globe")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(AppTheme.softBlue)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sourceManagerCard: some View {
        NavigationLink {
            SourceManagerView()
        } label: {
            HStack(spacing: 18) {
                Image(systemName: "cube")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 7) {
                    Text("书源管理")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                    Text("导入、测试、验证和管理网络书源")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.82))
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
            EmptyStateCard(
                systemImage: "newspaper",
                title: "暂无订阅源",
                message: "RSS/订阅源会在书源管理中统一导入和维护。"
            )

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
                SourceManagerView()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "globe")
                        .font(.system(size: 32, weight: .semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Web 写源")
                            .font(.title2.bold())
                        Text("用表单和网页辅助恢复 Flutter 版写源流程")
                            .font(.subheadline)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(20)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
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
                            results = filtered(allBooks, keyword: keyword)
                            hitSourceCount = hitSources.count
                        }
                    case .failure(let error):
                        failures.append("\(source.bookSourceName): \(error.displayMessage)")
                    }
                }
            }
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
