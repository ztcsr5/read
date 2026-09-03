import SwiftUI
import UIKit

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var pendingShelfAddBook: SearchBook?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    bookSearchTab

                }
                .padding(.horizontal, AppTheme.pagePadding)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .scrollDismissesKeyboard(.interactively)
            .pageBackground()
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.large)
            .task {
                viewModel.bind(appState: appState)
            }
            .confirmationDialog(
                "加入书架？",
                isPresented: Binding(
                    get: { pendingShelfAddBook != nil },
                    set: { if !$0 { pendingShelfAddBook = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("加入书架") {
                    guard let book = pendingShelfAddBook else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    appState.bookshelfStore.addOrUpdate(book)
                    pendingShelfAddBook = nil
                }
                Button("取消", role: .cancel) {
                    pendingShelfAddBook = nil
                }
            } message: {
                if let book = pendingShelfAddBook {
                    Text("确认把《\(book.name)》加入书架并开始跟踪阅读进度？")
                }
            }
        }
    }

    private var bookSearchTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 14) {
                searchField
                matchModePicker
                resultFilterPicker
            }
            .onChange(of: viewModel.matchMode) { _ in
                viewModel.applyMatchMode()
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
                    viewModel.startSearch()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { dismissKeyboard() }
                    }
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var resultFilterPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasUnfilteredResults {
                Picker("筛选范围", selection: $viewModel.resultFilterScope) {
                    ForEach(SearchResultFilterScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                TextField(viewModel.resultFilterScope.placeholder, text: $viewModel.resultFilter)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: viewModel.resultFilter) { _ in viewModel.applyResultFilter() }
                    .onChange(of: viewModel.resultFilterScope) { _ in viewModel.applyResultFilter() }
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
        } else if viewModel.hasUnfilteredResults && viewModel.results.isEmpty {
            EmptyStateCard(systemImage: "line.3.horizontal.decrease.circle", title: "没有符合筛选的结果", message: "换一个筛选词，或切换书名、作者、来源范围。")
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
                Text("已检测 \(viewModel.checkedSourceCount)/\(appState.sourceStore.sources.count) 个源 · 命中 \(viewModel.hitSourceCount) 个源 · 结果 \(viewModel.totalResultCount) 条\(viewModel.filterSummary)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !viewModel.sourceFailures.isEmpty {
                DisclosureGroup("有 \(viewModel.sourceFailures.count) 个源未返回结果") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(viewModel.sourceFailures, id: \.self) { failure in
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            ForEach(viewModel.results) { book in
                searchResultCard(book)
            }
        }
    }

    private func searchResultCard(_ book: SearchBook) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink {
                BookDetailView(book: book)
            } label: {
                SearchBookRow(book: book)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if !appState.bookshelfStore.contains(book) {
                    pendingShelfAddBook = book
                }
            } label: {
                Image(systemName: appState.bookshelfStore.contains(book) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(appState.bookshelfStore.contains(book) ? Color.green : AppTheme.accent)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appState.bookshelfStore.contains(book) ? "已在书架" : "加入书架")
        }
        .podcastCard()
    }

}

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var keyword = ""
    @Published var matchMode: SearchMatchMode = .exact
    @Published var resultFilterScope: SearchResultFilterScope = .all
    @Published var resultFilter = ""
    @Published var results: [SearchBook] = []
    private var unfilteredResults: [SearchBook] = []
    var hasUnfilteredResults: Bool { !unfilteredResults.isEmpty }
    var filterSummary: String {
        resultFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " · 筛选后 \(results.count) 条"
    }
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hitSourceCount = 0
    @Published var checkedSourceCount = 0
    @Published var totalResultCount = 0
    @Published var sourceFailures: [String] = []

    private weak var appState: AppState?
    private var activeSearchID: UUID?
    private var searchTask: Task<Void, Never>?
    private var activeKeyword = ""
    private var rawResults: [SearchBook] = []

    func bind(appState: AppState) {
        self.appState = appState
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        activeSearchID = nil
        isSearching = false
    }

    func startSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            await self?.search()
            self?.searchTask = nil
        }
    }

    func applyResultFilter() {
        // Search results are already deduplicated by the source search. This only
        // changes the visible projection, so changing the filter never re-runs IO.
        results = SearchResultFilter.apply(unfilteredResults, query: resultFilter, scope: resultFilterScope)
    }

    func applyMatchMode() {
        guard !activeKeyword.isEmpty, !rawResults.isEmpty else { return }
        unfilteredResults = filtered(rawResults, keyword: activeKeyword)
        totalResultCount = rawResults.count
        applyResultFilter()
    }

    func search() async {
        guard let appState else { return }
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        activeKeyword = keyword

        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        errorMessage = nil
        results = []
        unfilteredResults = []
        rawResults = []
        resultFilter = ""
        resultFilterScope = .all
        totalResultCount = 0
        sourceFailures = []
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
            guard activeSearchID == searchID, !Task.isCancelled else { return }
            await withTaskGroup(of: (BookSource, Result<[SearchBook], SourceEngineError>).self) { group in
                for source in batch {
                    group.addTask {
                        let result = await AsyncTimeout.run(seconds: 10) {
                            await engine.searchBooks(source: source, keyword: keyword, page: 1)
                        } ?? .failure(.network("Search timed out"))
                        return (source, result)
                    }
                }

                for await (source, result) in group {
                    guard activeSearchID == searchID, !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    checkedSourceCount += 1
                    switch result {
                    case .success(let books):
                        if !books.isEmpty {
                            hitSources.insert(source.bookSourceUrl)
                            allBooks.append(contentsOf: books)
                            rawResults = allBooks
                            totalResultCount = allBooks.count
                            hitSourceCount = hitSources.count
                        }
                    case .failure(let error):
                        let message = "\(source.bookSourceName): \(error.displayMessage)"
                        failures.append(message)
                        sourceFailures = Array(failures.suffix(40))
                    }
                    if checkedSourceCount % 6 == 0 || !allBooks.isEmpty && checkedSourceCount % 3 == 0 {
                        unfilteredResults = filtered(allBooks, keyword: keyword)
                        results = unfilteredResults
                        applyResultFilter()
                        totalResultCount = allBooks.count
                    }
                }
            }
            unfilteredResults = filtered(allBooks, keyword: keyword)
            results = unfilteredResults
            applyResultFilter()
            totalResultCount = allBooks.count
            hitSourceCount = hitSources.count
        }

        guard activeSearchID == searchID else { return }
        totalResultCount = allBooks.count
        unfilteredResults = filtered(allBooks, keyword: keyword)
        results = unfilteredResults
        applyResultFilter()
        hitSourceCount = hitSources.count
        if results.isEmpty {
            errorMessage = failures.isEmpty ? "没有搜索结果，请检查关键词或书源规则。" : failures.prefix(8).joined(separator: "\n")
        }
    }

    private func filtered(_ books: [SearchBook], keyword: String) -> [SearchBook] {
        SearchBookMatcher.filteredAndRanked(
            books,
            keyword: keyword,
            exact: matchMode == .exact
        )
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
