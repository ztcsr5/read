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
    @State private var sourceJSONEditor: SourceJSONEditorState?
    @State private var jsonPreview: SourceJSONPreview?
    @State private var sourceTest: SourceTestState?
    @State private var batchCheck: SourceBatchCheckState?
    @State private var isManagingBookSources = false
    @State private var selectedBookSourceURLs: Set<String> = []
    @State private var pendingDeleteBookSourceURLs: Set<String> = []

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
            .scrollDismissesKeyboard(.interactively)
            .pageBackground()
            .navigationTitle("源管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedTab == .bookSources, !appState.sourceStore.sources.isEmpty {
                        Button(isManagingBookSources ? "完成" : "管理") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isManagingBookSources.toggle()
                                if !isManagingBookSources {
                                    selectedBookSourceURLs.removeAll()
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
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
            .sheet(item: $sourceJSONEditor) { editor in
                sourceJSONEditorSheet(editor)
            }
            .sheet(item: $jsonPreview) { preview in
                jsonPreviewSheet(preview)
            }
            .sheet(item: $sourceTest) { state in
                sourceTestSheet(state)
            }
            .sheet(item: $batchCheck) { state in
                batchCheckSheet(state)
            }
            .alert("删除选中的书源？", isPresented: Binding(
                get: { !pendingDeleteBookSourceURLs.isEmpty },
                set: { if !$0 { pendingDeleteBookSourceURLs.removeAll() } }
            )) {
                Button("取消", role: .cancel) {
                    pendingDeleteBookSourceURLs.removeAll()
                }
                Button("删除", role: .destructive) {
                    appState.sourceStore.remove(sourceURLs: pendingDeleteBookSourceURLs)
                    selectedBookSourceURLs.removeAll()
                    pendingDeleteBookSourceURLs.removeAll()
                }
            } message: {
                Text("将删除 \(pendingDeleteBookSourceURLs.count) 个书源。此操作不会删除书架里的书，但对应书籍可能需要换源后才能继续加载。")
            }
            .sheet(isPresented: $showFileImporter) {
                UniversalDocumentPicker(
                    contentTypes: [.json, .plainText, .text, .data, .content, .item],
                    onPick: { urls in
                        showFileImporter = false
                        importFile(.success(urls))
                    },
                    onCancel: { showFileImporter = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    private var webServiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "globe")
                    .font(.title3)
                Text("源库状态")
                    .font(.headline)
                Spacer()
                Text("\(sourceCounts.total)")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
            }
            HStack(spacing: 10) {
                statusPill("书源 \(sourceCounts.books)", color: .blue)
                statusPill("仓库 \(sourceCounts.catalogs)", color: .purple)
                statusPill("RSS \(sourceCounts.rss)", color: .orange)
            }
            HStack(spacing: 10) {
                Button {
                    let enabled = appState.sourceStore.sources.filter(\.enabled)
                    batchCheck = SourceBatchCheckState(sources: enabled)
                } label: {
                    Label("一键检测启用书源", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.sourceStore.sources.filter(\.enabled).isEmpty)

                Button {
                    showImportSheet = true
                } label: {
                    Label("导入", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Text("支持本地 JSON、URL、阅读分享链接、仓库导入、RSS 预览和书源搜索/详情/目录/正文链路测试。")
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
        .onChange(of: selectedTab) { _ in
            searchText = ""
            isManagingBookSources = false
            selectedBookSourceURLs.removeAll()
        }
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
            if isManagingBookSources {
                bookSourceBatchToolbar
            }
            if appState.sourceStore.sources.isEmpty {
                EmptyStateCard(systemImage: "tray", title: "暂无书源", message: "点击右上角 + 导入书源 JSON")
            } else if filteredBookSources.isEmpty {
                CenterTextEmptyState("没有匹配的书源", minHeight: 220)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredBookSources) { source in
                        if isManagingBookSources {
                            selectableBookSourceRow(source)
                        } else {
                            bookSourceRow(source)
                        }
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
                        NavigationLink {
                            RSSArticlesView(source: source)
                        } label: {
                            rssRow(source)
                        }
                        .buttonStyle(.plain)
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
        return sourceCard(
            title: source.bookSourceName,
            subtitle: source.bookSourceUrl,
            group: source.bookSourceGroup,
            enabled: source.enabled,
            badges: source.ruleSearch == nil ? [] : ["可搜索"],
            health: appState.sourceHealthStore.record(for: source),
            actions: {
                Button(source.enabled ? "停用" : "启用") {
                    appState.sourceStore.setEnabled(!source.enabled, for: [source.bookSourceUrl])
                }
                Button("测试书源") {
                    sourceTest = SourceTestState(source: source)
                }
                Button("编辑 JSON") {
                    sourceJSONEditor = SourceJSONEditorState(title: source.bookSourceName, json: prettyJSON(source))
                }
                Button("删除", role: .destructive) {
                    appState.sourceStore.remove(source)
                }
            }
        )
    }

    private var bookSourceBatchToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("全选") {
                    selectedBookSourceURLs = Set(filteredBookSources.map(\.bookSourceUrl))
                }
                Button("反选") {
                    let visible = Set(filteredBookSources.map(\.bookSourceUrl))
                    selectedBookSourceURLs = visible.subtracting(selectedBookSourceURLs)
                }
                Button("清空") {
                    selectedBookSourceURLs.removeAll()
                }
                Spacer()
                Text("已选 \(selectedBookSourceURLs.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                Button("启用") {
                    appState.sourceStore.setEnabled(true, for: selectedBookSourceURLs)
                    selectedBookSourceURLs.removeAll()
                }
                .disabled(selectedBookSourceURLs.isEmpty)

                Button("停用") {
                    appState.sourceStore.setEnabled(false, for: selectedBookSourceURLs)
                    selectedBookSourceURLs.removeAll()
                }
                .disabled(selectedBookSourceURLs.isEmpty)

                Button("批量测试") {
                    let selected = filteredBookSources.filter { selectedBookSourceURLs.contains($0.bookSourceUrl) }
                    batchCheck = SourceBatchCheckState(sources: selected)
                }
                .disabled(selectedBookSourceURLs.isEmpty)

                Button("删除", role: .destructive) {
                    pendingDeleteBookSourceURLs = selectedBookSourceURLs
                }
                .disabled(selectedBookSourceURLs.isEmpty)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(AppTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func selectableBookSourceRow(_ source: BookSource) -> some View {
        Button {
            if selectedBookSourceURLs.contains(source.bookSourceUrl) {
                selectedBookSourceURLs.remove(source.bookSourceUrl)
            } else {
                selectedBookSourceURLs.insert(source.bookSourceUrl)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedBookSourceURLs.contains(source.bookSourceUrl) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedBookSourceURLs.contains(source.bookSourceUrl) ? AppTheme.accent : .secondary)
                    .frame(width: 32, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text(source.bookSourceName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text([source.bookSourceUrl, source.bookSourceGroup].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        statusBadge(source.enabled ? "启用" : "停用", color: source.enabled ? .green : .gray)
                        if source.ruleSearch != nil {
                            statusBadge("可搜索", color: .blue)
                        }
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func catalogRow(_ catalog: SourceCatalog) -> some View {
        let badges = catalog.importedCount > 0 ? ["仓库", "已导入 \(catalog.importedCount)"] : ["仓库"]
        let statusLine = [
            catalog.group,
            catalog.lastImportedAt.map { "最近导入 \($0.formatted(date: .abbreviated, time: .shortened))" }
        ].compactMap { $0 }.joined(separator: " · ").nilIfEmpty

        return sourceCard(
            title: catalog.name,
            subtitle: catalog.importUrl ?? catalog.url,
            group: statusLine,
            enabled: catalog.enabled,
            badges: badges,
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
            badges: ["RSS", "文章"],
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
        health: SourceHealthRecord? = nil,
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
                if let health {
                    HStack(spacing: 6) {
                        Image(systemName: health.status.systemImage)
                        Text("\(health.status.title) · \(health.testedAt.formatted(date: .abbreviated, time: .shortened))")
                            .lineLimit(1)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(health.status.color)
                    Text(health.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
        statusPill(text, color: color)
    }

    private func statusPill(_ text: String, color: Color) -> some View {
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
        if let lastError = appState.sourceHealthStore.lastError {
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showFileImporter = true
                        }
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { dismissKeyboard() }
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

    private func sourceJSONEditorSheet(_ editor: SourceJSONEditorState) -> some View {
        NavigationStack {
            VStack(spacing: 10) {
                TextEditor(text: Binding(
                    get: { sourceJSONEditor?.json ?? editor.json },
                    set: { sourceJSONEditor?.json = $0 }
                ))
                .font(.system(.footnote, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .background(AppTheme.elevatedCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("保存会按 bookSourceUrl 覆盖同一书源。建议只编辑你确认的字段。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .navigationTitle(editor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { sourceJSONEditor = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveSourceJSONEditor()
                    }
                }
            }
        }
        .presentationDetents([.large])
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

    private func batchCheckSheet(_ state: SourceBatchCheckState) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("将按顺序测试 \(state.sources.count) 个书源的搜索阶段。搜索通过后，可再进入单源深测验证详情、目录和正文。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("测试关键词", text: Binding(
                    get: { batchCheck?.keyword ?? state.keyword },
                    set: { batchCheck?.keyword = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)

                HStack {
                    Button {
                        Task { await runBatchSourceCheck() }
                    } label: {
                        Label(batchCheck?.isRunning == true ? "测试中..." : "开始批量测试", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(batchCheck?.isRunning == true || state.sources.isEmpty)

                    if let current = batchCheck, current.isRunning {
                        Text("\(current.checkedCount)/\(current.sources.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                List {
                    let results = batchCheck?.results ?? state.results
                    if results.isEmpty {
                        Text("尚未开始。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: result.status.systemImage)
                                        .foregroundStyle(result.status.color)
                                    Text(result.sourceName)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(result.status.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(result.status.color)
                                }
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(result.sourceURL)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("批量测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { batchCheck = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func importSources() {
        do {
            let parsed = SourceImportLinkParser.parse(importText)
            let report: SourceImportReport
            switch parsed.kind {
            case .empty:
                throw SourceImportError.empty
            case .json:
                report = try appState.sourceStore.importJSON(parsed.value)
            case .url:
                throw SourceImportError.urlImportRequired(parsed.value)
            case .unsupportedScheme:
                throw SourceImportError.unsupportedScheme
            case .unknown:
                throw SourceImportError.unknownInput
            }
            importText = ""
            importError = nil
            importMessage = report.userMessage
            showImportSheet = false
        } catch {
            importMessage = nil
            importError = error.localizedDescription
        }
    }

    private func saveSourceJSONEditor() {
        guard let editor = sourceJSONEditor else { return }
        do {
            let source = try appState.sourceStore.upsertBookSourceJSON(editor.json)
            importError = nil
            importMessage = "已保存书源：\(source.bookSourceName)"
            sourceJSONEditor = nil
        } catch {
            importMessage = nil
            importError = "JSON 保存失败：\(error.localizedDescription)"
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
        state.output = sourceTestHeader(source: state.source, keyword: keyword)
        sourceTest = state

        let result = await appState.engine.searchBooks(source: state.source, keyword: keyword, page: 1)
        guard var latest = sourceTest else { return }
        latest.isRunning = false
        switch result {
        case .success(let books):
            let preview = books.prefix(10).enumerated().map { index, book in
                "\(index + 1). \(book.name) | \(book.author ?? "未知作者")\n   \(book.bookUrl)"
            }.joined(separator: "\n")
            var output = sourceTestHeader(source: state.source, keyword: keyword)
            output += "\n\n[PASS] 搜索：\(books.count) 条结果"
            if preview.isEmpty {
                output += "\n[WARN] 搜索请求成功但列表为空。建议检查 keyword/page 占位符、搜索规则列表选择器或接口返回结构。"
            } else {
                output += "\n\n\(preview)"
            }
            if let first = books.first {
                output += "\n\n正在验证首条结果详情..."
                latest.output = output
                sourceTest = latest
                switch await appState.engine.getBookDetail(source: state.source, book: first) {
                case .success(let detail):
                    output += "\n[PASS] 详情：\(detail.name)"
                    switch await appState.engine.getChapterList(source: state.source, book: detail) {
                    case .success(let chapters):
                        output += "\n[PASS] 目录：\(chapters.count) 章"
                        if let chapter = chapters.first {
                            switch await appState.engine.getContent(source: state.source, chapter: chapter) {
                            case .success(let content):
                                output += "\n[PASS] 正文：\(content.paragraphs.count) 段"
                                if content.paragraphs.isEmpty {
                                    output += "\n[WARN] 正文解析为空。建议检查 ruleContent.content / content 正则清洗是否过度。"
                                } else {
                                    output += "\n\n首段预览：\(content.paragraphs.first?.prefix(120) ?? "")"
                                }
                            case .failure(let error):
                                output += sourceTestFailure(stage: "正文", error: error)
                            }
                        } else {
                            output += "\n[WARN] 目录为空，无法验证正文。建议检查 ruleToc.chapterList / chapterName / chapterUrl。"
                        }
                    case .failure(let error):
                        output += sourceTestFailure(stage: "目录", error: error)
                    }
                case .failure(let error):
                    output += sourceTestFailure(stage: "详情", error: error)
                }
            }
            latest.output = output
        case .failure(let error):
            latest.output = sourceTestHeader(source: state.source, keyword: keyword)
                + sourceTestFailure(stage: "搜索", error: error)
        }
        sourceTest = latest
    }

    @MainActor
    private func runBatchSourceCheck() async {
        guard var state = batchCheck else { return }
        let keyword = state.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            state.results = [
                SourceBatchCheckResult(
                    sourceName: "批量测试",
                    sourceURL: "",
                    status: .failed,
                    message: "请输入测试关键词。"
                )
            ]
            batchCheck = state
            return
        }

        state.isRunning = true
        state.checkedCount = 0
        state.results = []
        batchCheck = state

        for source in state.sources {
            let result = await appState.engine.searchBooks(source: source, keyword: keyword, page: 1)
            guard var latest = batchCheck else { return }
            latest.checkedCount += 1
            switch result {
            case .success(let books):
                let status: SourceBatchCheckStatus = books.isEmpty ? .warning : .passed
                let message = books.isEmpty
                    ? "搜索请求成功但结果为空，优先检查 searchUrl、分页占位符和 ruleSearch.bookList。"
                    : "搜索通过：\(books.count) 条结果。"
                latest.results.append(
                    SourceBatchCheckResult(
                        sourceName: source.bookSourceName,
                        sourceURL: source.bookSourceUrl,
                        status: status,
                        message: message
                    )
                )
                appState.sourceHealthStore.record(
                    source: source,
                    status: status.healthStatus,
                    message: message,
                    keyword: keyword,
                    resultCount: books.count
                )
            case .failure(let error):
                let message = "\(error.displayMessage)；建议：\(sourceTestAdvice(stage: "搜索", error: error))"
                latest.results.append(
                    SourceBatchCheckResult(
                        sourceName: source.bookSourceName,
                        sourceURL: source.bookSourceUrl,
                        status: .failed,
                        message: message
                    )
                )
                appState.sourceHealthStore.record(
                    source: source,
                    status: .failed,
                    message: message,
                    keyword: keyword,
                    resultCount: 0
                )
            }
            batchCheck = latest
        }

        guard var finished = batchCheck else { return }
        finished.isRunning = false
        batchCheck = finished
    }

    private func sourceTestHeader(source: BookSource, keyword: String) -> String {
        """
        书源诊断
        源：\(source.bookSourceName)
        URL：\(source.bookSourceUrl)
        关键词：\(keyword)

        规则覆盖：
        \(sourceRuleCoverage(source))

        正在执行链路：搜索 -> 详情 -> 目录 -> 正文
        """
    }

    private func sourceRuleCoverage(_ source: BookSource) -> String {
        let items = [
            ("searchUrl", source.searchUrl?.nilIfEmpty != nil),
            ("ruleSearch", source.ruleSearch != nil),
            ("ruleBookInfo", source.ruleBookInfo != nil),
            ("ruleToc", source.ruleToc != nil),
            ("ruleContent", source.ruleContent != nil),
            ("header", source.header?.nilIfEmpty != nil || source.raw["bookSourceHeader"]?.nilIfEmpty != nil),
            ("customConfig", source.customConfig?.nilIfEmpty != nil)
        ]
        return items
            .map { "\($0.1 ? "[OK]" : "[--]") \($0.0)" }
            .joined(separator: "\n")
    }

    private func sourceTestFailure(stage: String, error: SourceEngineError) -> String {
        "\n[FAIL] \(stage)：\(error.displayMessage)\n建议：\(sourceTestAdvice(stage: stage, error: error))"
    }

    private func sourceTestAdvice(stage: String, error: SourceEngineError) -> String {
        let message = error.displayMessage.lowercased()
        if message.contains("unsupported") || message.contains("javascript") || message.contains("js") {
            return "优先检查书源 JS API 兼容；如果旧阅读能跑，通常需要补 java/ajax/base64/加密或变量桥接。"
        }
        if message.contains("empty") || message.contains("空") {
            return "网络有返回但内容为空，优先检查请求方式、Header/Cookie、charset、反爬或 WebView fallback。"
        }
        if message.contains("url") || message.contains("invalid") || message.contains("无效") {
            return "优先检查相对 URL 拼接、searchUrl 模板、@Header/@Body 指令和 encode 规则。"
        }
        switch stage {
        case "搜索":
            return "重点看 searchUrl、ruleSearch.bookList/name/author/bookUrl；如果搜索为空，换关键词再测一次。"
        case "详情":
            return "重点看搜索结果 bookUrl 是否正确、详情页是否需要 Cookie/Header、ruleBookInfo 字段名是否兼容。"
        case "目录":
            return "重点看 ruleToc.chapterList/chapterName/chapterUrl，以及目录是否由 JS 延迟加载。"
        case "正文":
            return "重点看 ruleContent.content、正文净化 replaceRegex，以及章节 URL 是否需要 Referer。"
        default:
            return "按当前失败阶段检查对应规则和请求配置。"
        }
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
        await importFromURL(catalogURL: catalog.url)
    }

    private func pasteFromClipboard() {
        importText = UIPasteboard.general.string ?? ""
        importMessage = importText.isEmpty ? nil : "已从剪贴板粘贴"
        importError = importText.isEmpty ? "剪贴板没有文本" : nil
    }

    private func importFromURL(catalogURL: String? = nil) async {
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
            let report = try appState.sourceStore.importJSON(decoded)
            if let catalogURL {
                appState.sourceStore.recordCatalogImport(url: catalogURL, report: report)
            }
            importURL = ""
            importError = nil
            importMessage = "URL \(report.userMessage)"
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
            let report = try appState.sourceStore.importJSON(text)
            importError = nil
            importMessage = "文件 \(report.userMessage)"
            showImportSheet = false
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

private struct SourceJSONEditorState: Identifiable {
    let id = UUID()
    let title: String
    var json: String
}

private struct SourceTestState: Identifiable {
    let id = UUID()
    let source: BookSource
    var keyword = "斗破苍穹"
    var isRunning = false
    var output: String?
}

private struct SourceBatchCheckState: Identifiable {
    let id = UUID()
    let sources: [BookSource]
    var keyword = "斗破苍穹"
    var isRunning = false
    var checkedCount = 0
    var results: [SourceBatchCheckResult] = []
}

private struct SourceBatchCheckResult: Identifiable {
    let id = UUID()
    let sourceName: String
    let sourceURL: String
    let status: SourceBatchCheckStatus
    let message: String
}

private extension SourceHealthStatus {
    var title: String {
        switch self {
        case .passed: return "上次通过"
        case .warning: return "上次警告"
        case .failed: return "上次失败"
        }
    }

    var systemImage: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}

private enum SourceBatchCheckStatus {
    case passed
    case warning
    case failed

    var healthStatus: SourceHealthStatus {
        switch self {
        case .passed: return .passed
        case .warning: return .warning
        case .failed: return .failed
        }
    }

    var title: String {
        switch self {
        case .passed: return "PASS"
        case .warning: return "WARN"
        case .failed: return "FAIL"
        }
    }

    var systemImage: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
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
