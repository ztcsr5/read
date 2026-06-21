import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SourceManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: SourceManagerTab = .bookSources
    @State private var searchText = ""
    @State private var importText = ""
    @State private var importURL = ""
    @State private var importError: String?
    @State private var importMessage: String?
    @State private var showFileImporter = false
    @State private var showImportSheet = false
    @State private var showUnavailableNotice = false
    @State private var jsonPreview: SourceJSONPreview?
    @State private var sourceTest: SourceTestState?

    private var filteredBookSources: [BookSource] {
        let keyword = normalizedSearchText
        guard !keyword.isEmpty else { return appState.sourceStore.sources }
        return appState.sourceStore.sources.filter {
            [$0.bookSourceName, $0.bookSourceUrl, $0.bookSourceGroup ?? "", $0.searchUrl ?? ""]
                .contains { $0.lowercased().contains(keyword) }
        }
    }

    private var filteredRSSSources: [RSSSource] {
        let keyword = normalizedSearchText
        guard !keyword.isEmpty else { return appState.sourceStore.rssSources }
        return appState.sourceStore.rssSources.filter {
            [$0.sourceName, $0.sourceUrl, $0.sourceGroup ?? "", $0.sourceComment ?? ""]
                .contains { $0.lowercased().contains(keyword) }
        }
    }

    private var filteredCatalogs: [SourceCatalog] {
        let keyword = normalizedSearchText
        guard !keyword.isEmpty else { return appState.sourceStore.catalogs }
        return appState.sourceStore.catalogs.filter {
            [$0.name, $0.url, $0.group ?? "", $0.comment ?? ""]
                .contains { $0.lowercased().contains(keyword) }
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    webServiceCard
                    tabPicker
                    searchField
                    currentTabContent
                    importStatus
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 10)
            }
            .pageBackground()
            .navigationTitle("源管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImportSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("导入源")
                }
            }
            .sheet(isPresented: $showImportSheet) {
                importSheet
            }
            .sheet(item: $jsonPreview) { preview in
                jsonPreviewSheet(preview)
            }
            .sheet(item: $sourceTest) { state in
                sourceTestSheet(state)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .plainText, .data, .item],
                allowsMultipleSelection: false,
                onCompletion: importFile
            )
            .alert("功能正在恢复", isPresented: $showUnavailableNotice) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("测试源、JSON 编辑、仓库浏览和 RSS 阅读会继续按 Flutter 版补齐。当前先保证导入、分类、启停和删除可用。")
            }
        }
    }

    private var webServiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "globe")
                    .font(.title3)
                Text("Web 书源编辑服务")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding.constant(false))
                    .labelsHidden()
                    .disabled(true)
            }
            Text("本地 Web 编辑服务会在核心导入和新 Swift 书源引擎稳定后恢复。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .podcastCard()
    }

    private var tabPicker: some View {
        Picker("源类型", selection: $selectedTab) {
            ForEach(SourceManagerTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedTab) { _ in searchText = "" }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索名称、地址、分组", text: $searchText)
                .textInputAutocapitalization(.never)
        }
        .padding(12)
        .background(AppTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var currentTabContent: some View {
        switch selectedTab {
        case .bookSources:
            bookSourceContent
        case .catalogs:
            catalogContent
        case .rss:
            rssContent
        }
    }

    private var bookSourceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "书源", count: appState.sourceStore.sources.count)
            if appState.sourceStore.sources.isEmpty {
                EmptyStateCard(systemImage: "tray", title: "暂无书源", message: "点击右上角 + 导入书源 JSON")
            } else if filteredBookSources.isEmpty {
                CenterTextEmptyState("没有匹配的书源", minHeight: 220)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredBookSources) { source in
                        bookSourceRow(source)
                    }
                }
            }
        }
    }

    private var catalogContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "书源仓库", count: appState.sourceStore.catalogs.count)
            if appState.sourceStore.catalogs.isEmpty {
                EmptyStateCard(systemImage: "square.stack", title: "暂无书源仓库", message: "导入仓库 JSON 后会显示在这里")
            } else if filteredCatalogs.isEmpty {
                CenterTextEmptyState("没有匹配的仓库", minHeight: 220)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredCatalogs) { catalog in
                        catalogRow(catalog)
                    }
                }
            }
        }
    }

    private var rssContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "RSS", count: appState.sourceStore.rssSources.count)
            if appState.sourceStore.rssSources.isEmpty {
                EmptyStateCard(systemImage: "newspaper", title: "暂无 RSS", message: "导入 RSS/Atom JSON 后会显示在这里")
            } else if filteredRSSSources.isEmpty {
                CenterTextEmptyState("没有匹配的 RSS", minHeight: 220)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredRSSSources) { source in
                        rssRow(source)
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AppTheme.accent.opacity(0.12))
                .foregroundStyle(AppTheme.accent)
                .clipShape(Capsule())
        }
    }

    private func bookSourceRow(_ source: BookSource) -> some View {
        sourceCard(
            title: source.bookSourceName,
            subtitle: source.bookSourceUrl,
            group: source.bookSourceGroup,
            enabled: source.enabled,
            badges: source.ruleSearch == nil ? [] : ["可搜索"],
            actions: {
                Button(source.enabled ? "停用" : "启用") {
                    appState.sourceStore.setEnabled(!source.enabled, for: [source.bookSourceUrl])
                }
                Button("测试书源") {
                    sourceTest = SourceTestState(source: source)
                }
                Button("查看 JSON") {
                    jsonPreview = SourceJSONPreview(title: source.bookSourceName, json: prettyJSON(source))
                }
                Button("删除", role: .destructive) {
                    appState.sourceStore.remove(source)
                }
            }
        )
    }

    private func catalogRow(_ catalog: SourceCatalog) -> some View {
        sourceCard(
            title: catalog.name,
            subtitle: catalog.importUrl ?? catalog.url,
            group: catalog.group,
            enabled: catalog.enabled,
            badges: ["仓库"],
            actions: {
                Button(catalog.enabled ? "停用" : "启用") {
                    appState.sourceStore.setCatalogsEnabled(!catalog.enabled, for: [catalog.url])
                }
                Button("导入仓库") {
                    Task { await importCatalog(catalog) }
                }
                Button("查看 JSON") {
                    jsonPreview = SourceJSONPreview(title: catalog.name, json: prettyJSON(catalog))
                }
                Button("删除", role: .destructive) {
                    appState.sourceStore.removeCatalogs(urls: [catalog.url])
                }
            }
        )
    }

    private func rssRow(_ source: RSSSource) -> some View {
        sourceCard(
            title: source.sourceName,
            subtitle: source.sourceUrl,
            group: source.sourceGroup,
            enabled: source.enabled,
            badges: ["RSS"],
            actions: {
                Button(source.enabled ? "停用" : "启用") {
                    appState.sourceStore.setRSSEnabled(!source.enabled, for: [source.sourceUrl])
                }
                Button("查看 JSON") {
                    jsonPreview = SourceJSONPreview(title: source.sourceName, json: prettyJSON(source))
                }
                Button("删除", role: .destructive) {
                    appState.sourceStore.removeRSS(sourceURLs: [source.sourceUrl])
                }
            }
        )
    }

    private func sourceCard<MenuContent: View>(
        title: String,
        subtitle: String,
        group: String?,
        enabled: Bool,
        badges: [String],
        @ViewBuilder actions: @escaping () -> MenuContent
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text([subtitle, group].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    statusBadge(enabled ? "启用" : "停用", color: enabled ? .green : .gray)
                    ForEach(badges, id: \.self) { badge in
                        statusBadge(badge, color: .blue)
                    }
                }
            }
            Spacer()
            Menu {
                actions()
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(14)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 5)
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var importStatus: some View {
        if let importMessage {
            Text(importMessage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)
        }
        if let importError {
            Text(importError)
                .font(.footnote)
                .foregroundStyle(.red)
        }
        if let lastError = appState.sourceStore.lastError {
            Text(lastError)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("支持书源 JSON、仓库 JSON、RSS/Atom、阅读导入链接、普通 URL 和网页分享文本。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("JSON URL，可选", text: $importURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 230)
                    .overlay(alignment: .topLeading) {
                        if importText.isEmpty {
                            Text("粘贴 JSON、HTTP 地址、分享文本或 yuedu:// / legado:// 链接")
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal)

                VStack(spacing: 10) {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showImportSheet = false
                        showFileImporter = true
                    } label: {
                        Label("选择本地 JSON 文件", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await importFromURL() }
                    } label: {
                        Label("从 URL 导入", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Task { await importSourcesSmart() }
                    } label: {
                        Label("自动识别并导入", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)

                importStatus
                    .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top)
            .navigationTitle("导入源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showImportSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        Task { await importSourcesSmart() }
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func jsonPreviewSheet(_ preview: SourceJSONPreview) -> some View {
        NavigationStack {
            ScrollView {
                Text(preview.json)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { jsonPreview = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("复制") {
                        UIPasteboard.general.string = preview.json
                        importMessage = "JSON 已复制到剪贴板"
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sourceTestSheet(_ state: SourceTestState) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(state.source.bookSourceUrl)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                TextField("测试关键词", text: Binding(
                    get: { sourceTest?.keyword ?? state.keyword },
                    set: { sourceTest?.keyword = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)

                Button {
                    Task { await runSourceTest() }
                } label: {
                    Label(sourceTest?.isRunning == true ? "测试中..." : "开始测试", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceTest?.isRunning == true)

                ScrollView {
                    Text(sourceTest?.output ?? "将执行搜索 URL、网络请求、解码和搜索规则解析。")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
            .padding()
            .navigationTitle(state.source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { sourceTest = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func importSources() {
        do {
            let before = sourceCounts
            try appState.sourceStore.importSmartInput(importText)
            let after = sourceCounts
            importText = ""
            importError = nil
            importMessage = "导入成功：书源 \(after.books)，仓库 \(after.catalogs)，RSS \(after.rss)，本次新增/更新约 \(after.total - before.total)"
            showImportSheet = false
        } catch {
            importMessage = nil
            importError = error.localizedDescription
        }
    }

    @MainActor
    private func runSourceTest() async {
        guard var state = sourceTest else { return }
        let keyword = state.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            state.output = "请输入测试关键词。"
            sourceTest = state
            return
        }
        state.isRunning = true
        state.output = "正在搜索：\(keyword)\n源：\(state.source.bookSourceName)"
        sourceTest = state

        let result = await appState.engine.searchBooks(source: state.source, keyword: keyword, page: 1)
        guard var latest = sourceTest else { return }
        latest.isRunning = false
        switch result {
        case .success(let books):
            let preview = books.prefix(10).enumerated().map { index, book in
                "\(index + 1). \(book.name) | \(book.author ?? "未知作者")\n   \(book.bookUrl)"
            }.joined(separator: "\n")
            latest.output = "搜索成功：\(books.count) 条结果\n\n\(preview)"
        case .failure(let error):
            latest.output = "测试失败：\(error.displayMessage)"
        }
        sourceTest = latest
    }

    private func importSourcesSmart() async {
        let parsed = SourceImportLinkParser.parse(importText)
        if parsed.kind == .url {
            importURL = parsed.value
            await importFromURL()
            return
        }
        importSources()
    }

    private func importCatalog(_ catalog: SourceCatalog) async {
        importURL = catalog.importUrl ?? catalog.url
        await importFromURL()
    }

    private func pasteFromClipboard() {
        importText = UIPasteboard.general.string ?? ""
        importMessage = importText.isEmpty ? nil : "已从剪贴板粘贴"
        importError = importText.isEmpty ? "剪贴板没有文本" : nil
    }

    private func importFromURL() async {
        do {
            let text = importURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: normalizeImportURL(text)) else {
                importError = "URL 无效"
                return
            }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 SourceReadSwift", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = ResponseTextDecoder().decode(data: data, headers: [:])
            if looksLikeCloudflareChallenge(decoded) {
                throw SourceImportError.challengePage
            }
            let before = sourceCounts
            try appState.sourceStore.importJSON(decoded)
            let after = sourceCounts
            importURL = ""
            importError = nil
            importMessage = "URL 导入成功：书源 \(after.books)，仓库 \(after.catalogs)，RSS \(after.rss)，本次新增/更新约 \(after.total - before.total)"
            showImportSheet = false
        } catch {
            importMessage = nil
            importError = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            let text = ResponseTextDecoder().decode(data: data, headers: [:])
            let before = sourceCounts
            try appState.sourceStore.importJSON(text)
            let after = sourceCounts
            importError = nil
            importMessage = "文件导入成功：书源 \(after.books)，仓库 \(after.catalogs)，RSS \(after.rss)，本次新增/更新约 \(after.total - before.total)"
        } catch {
            importMessage = nil
            importError = error.localizedDescription
        }
    }

    private var sourceCounts: (books: Int, catalogs: Int, rss: Int, total: Int) {
        let books = appState.sourceStore.sources.count
        let catalogs = appState.sourceStore.catalogs.count
        let rss = appState.sourceStore.rssSources.count
        return (books, catalogs, rss, books + catalogs + rss)
    }

    private func normalizeImportURL(_ value: String) -> String {
        if value.contains("github.com"), value.contains("/blob/") {
            return value
                .replacingOccurrences(of: "https://github.com/", with: "https://raw.githubusercontent.com/")
                .replacingOccurrences(of: "/blob/", with: "/")
        }
        return value
    }

    private func looksLikeCloudflareChallenge(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("cloudflare")
            && (lower.contains("challenge-platform") || lower.contains("cf-chl") || lower.contains("checking your browser"))
    }

    private func prettyJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

private struct SourceJSONPreview: Identifiable {
    let id = UUID()
    let title: String
    let json: String
}

private struct SourceTestState: Identifiable {
    let id = UUID()
    let source: BookSource
    var keyword = "斗破苍穹"
    var isRunning = false
    var output: String?
}

private enum SourceManagerTab: String, CaseIterable, Identifiable {
    case bookSources
    case catalogs
    case rss

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bookSources: return "书源"
        case .catalogs: return "仓库"
        case .rss: return "RSS"
        }
    }
}
