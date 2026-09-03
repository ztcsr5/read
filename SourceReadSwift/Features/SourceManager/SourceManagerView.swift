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
    @State private var openFileImporterAfterSheetDismiss = false
    @State private var sourceJSONEditor: SourceJSONEditorState?
    @State private var sourceRuleEditor: BookSource?
    @State private var jsonPreview: SourceJSONPreview?
    @State private var sourceTest: SourceTestState?
    @State private var batchCheck: SourceBatchCheckState?
    @State private var sourceLogin: BookSource?
    @State private var sourceHistory: BookSource?
    @State private var sourceVisualDetail: BookSource?
    @State private var rssEditor: RSSSource?
    @State private var isManagingBookSources = false
    @State private var selectedBookSourceURLs: Set<String> = []
    @State private var pendingDeleteBookSourceURLs: Set<String> = []
    @State private var isManagingCatalogs = false
    @State private var selectedCatalogURLs: Set<String> = []
    @State private var pendingDeleteCatalogURLs: Set<String> = []
    @State private var isManagingRSS = false
    @State private var selectedRSSURLs: Set<String> = []
    @State private var pendingDeleteRSSURLs: Set<String> = []

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

    private var currentTabCount: Int {
        switch selectedTab {
        case .bookSources: return appState.sourceStore.sources.count
        case .catalogs: return appState.sourceStore.catalogs.count
        case .rss: return appState.sourceStore.rssSources.count
        }
    }

    private var isManagingCurrentTab: Bool {
        switch selectedTab {
        case .bookSources: return isManagingBookSources
        case .catalogs: return isManagingCatalogs
        case .rss: return isManagingRSS
        }
    }

    private func toggleManagementForCurrentTab() {
        withAnimation(.easeOut(duration: 0.2)) {
            switch selectedTab {
            case .bookSources:
                isManagingBookSources.toggle()
                if !isManagingBookSources { selectedBookSourceURLs.removeAll() }
            case .catalogs:
                isManagingCatalogs.toggle()
                if !isManagingCatalogs { selectedCatalogURLs.removeAll() }
            case .rss:
                isManagingRSS.toggle()
                if !isManagingRSS { selectedRSSURLs.removeAll() }
            }
        }
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
                    if currentTabCount > 0 {
                        Button(isManagingCurrentTab ? "完成" : "管理") {
                            toggleManagementForCurrentTab()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            .onChange(of: showImportSheet) { isPresented in
                guard !isPresented, openFileImporterAfterSheetDismiss else { return }
                openFileImporterAfterSheetDismiss = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    showFileImporter = true
                }
            }
            .sheet(item: $sourceJSONEditor) { editor in
                sourceJSONEditorSheet(editor)
            }
            .sheet(item: $sourceRuleEditor) { source in
                SourceRuleEditorView(
                    source: source,
                    onSave: { updated in
                        do {
                            let data = try JSONEncoder().encode(updated)
                            _ = try appState.sourceStore.upsertBookSourceJSON(String(decoding: data, as: UTF8.self))
                            importError = nil
                            importMessage = "规则已保存：\(updated.bookSourceName)"
                            sourceRuleEditor = nil
                        } catch {
                            importMessage = nil
                            importError = "规则保存失败：\(error.localizedDescription)"
                        }
                    },
                    onCancel: { sourceRuleEditor = nil }
                )
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
            .sheet(item: $sourceLogin) { source in
                SourceLoginView(source: source, cookieStore: appState.sourceCookieStore)
            }
            .sheet(item: $sourceHistory) { source in
                SourceDiagnosticHistoryView(source: source)
                    .environmentObject(appState)
            }
            .sheet(item: $sourceVisualDetail) { source in
                SourceVisualDetailView(
                    source: source,
                    health: appState.sourceHealthStore.record(for: source),
                    onTest: { sourceTest = SourceTestState(source: source) },
                    onEditRules: { sourceRuleEditor = source },
                    onEditJSON: { sourceJSONEditor = SourceJSONEditorState(title: source.bookSourceName, json: prettyJSON(source)) }
                )
                .environmentObject(appState)
            }
            .sheet(item: $rssEditor) { source in
                RSSSourceEditorView(source: source) { updated in
                    do {
                        _ = try appState.sourceStore.upsertRSSSource(updated)
                        importError = nil
                        importMessage = "RSS 已保存：\(updated.sourceName)"
                    } catch {
                        importMessage = nil
                        importError = "RSS 保存失败：\(error.localizedDescription)"
                    }
                }
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
            .alert("删除选中的书源仓库？", isPresented: Binding(
                get: { !pendingDeleteCatalogURLs.isEmpty },
                set: { if !$0 { pendingDeleteCatalogURLs.removeAll() } }
            )) {
                Button("取消", role: .cancel) { pendingDeleteCatalogURLs.removeAll() }
                Button("删除", role: .destructive) {
                    appState.sourceStore.removeCatalogs(urls: pendingDeleteCatalogURLs)
                    selectedCatalogURLs.removeAll()
                    pendingDeleteCatalogURLs.removeAll()
                }
            } message: {
                Text("将删除 \(pendingDeleteCatalogURLs.count) 个书源仓库，已经导入的书源不会被删除。")
            }
            .alert("删除选中的 RSS？", isPresented: Binding(
                get: { !pendingDeleteRSSURLs.isEmpty },
                set: { if !$0 { pendingDeleteRSSURLs.removeAll() } }
            )) {
                Button("取消", role: .cancel) { pendingDeleteRSSURLs.removeAll() }
                Button("删除", role: .destructive) {
                    appState.sourceStore.removeRSS(sourceURLs: pendingDeleteRSSURLs)
                    selectedRSSURLs.removeAll()
                    pendingDeleteRSSURLs.removeAll()
                }
            } message: {
                Text("将删除 \(pendingDeleteRSSURLs.count) 个 RSS 源及其入口，已缓存的文章内容不受影响。")
            }
            .sheet(isPresented: $showFileImporter) {
                UniversalDocumentPicker(
                    contentTypes: [
                        .json,
                        .plainText,
                        .text,
                        .data,
                        .content,
                        .item,
                        UTType(importedAs: "com.edc21.sourceread.source-json"),
                        UTType(filenameExtension: "json") ?? .json,
                        UTType(filenameExtension: "txt") ?? .plainText,
                        UTType(filenameExtension: "text") ?? .text
                    ],
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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let enabled = appState.sourceStore.sources.filter(\.enabled)
                    batchCheck = SourceBatchCheckState(sources: enabled)
                } label: {
                    Label("检测启用书源", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(appState.sourceStore.sources.filter(\.enabled).isEmpty)
                Spacer()
                Text("导入请使用右上角 +")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("支持 JSON、URL、阅读分享链接、仓库、RSS，以及搜索 → 详情 → 目录 → 正文全链路测试。")
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
            isManagingCatalogs = false
            isManagingRSS = false
            selectedBookSourceURLs.removeAll()
            selectedCatalogURLs.removeAll()
            selectedRSSURLs.removeAll()
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
            if isManagingCatalogs {
                catalogBatchToolbar
            }
            if appState.sourceStore.catalogs.isEmpty {
                EmptyStateCard(systemImage: "square.stack", title: "暂无书源仓库", message: "导入仓库 JSON 后会显示在这里")
            } else if filteredCatalogs.isEmpty {
                CenterTextEmptyState("没有匹配的仓库", minHeight: 220)
            } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredCatalogs) { catalog in
                            if isManagingCatalogs {
                                selectableCatalogRow(catalog)
                            } else {
                                catalogRow(catalog)
                            }
                        }
                }
            }
        }
    }

    private var rssContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "RSS", count: appState.sourceStore.rssSources.count)
            if isManagingRSS {
                rssBatchToolbar
            }
            if appState.sourceStore.rssSources.isEmpty {
                EmptyStateCard(systemImage: "newspaper", title: "暂无 RSS", message: "导入 RSS/Atom JSON 后会显示在这里")
            } else if filteredRSSSources.isEmpty {
                CenterTextEmptyState("没有匹配的 RSS", minHeight: 220)
            } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredRSSSources) { source in
                            if isManagingRSS {
                                selectableRSSRow(source)
                            } else {
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
                Button("可视化详情") {
                    sourceVisualDetail = source
                }
                Button("诊断历史") {
                    sourceHistory = source
                }
                Button("编辑 JSON") {
                    sourceJSONEditor = SourceJSONEditorState(title: source.bookSourceName, json: prettyJSON(source))
                }
                Button("规则编辑") {
                    sourceRuleEditor = source
                }
                if source.loginUrl?.nilIfEmpty != nil {
                    Button("打开登录页") {
                        sourceLogin = source
                    }
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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

    private var catalogBatchToolbar: some View {
        batchToolbar(
            selectedCount: selectedCatalogURLs.count,
            visibleIDs: Set(filteredCatalogs.map(\.url)),
            onSelect: { selectedCatalogURLs = $0 },
            onEnable: { appState.sourceStore.setCatalogsEnabled(true, for: selectedCatalogURLs); selectedCatalogURLs.removeAll() },
            onDisable: { appState.sourceStore.setCatalogsEnabled(false, for: selectedCatalogURLs); selectedCatalogURLs.removeAll() },
            onDelete: { pendingDeleteCatalogURLs = selectedCatalogURLs }
        )
    }

    private var rssBatchToolbar: some View {
        batchToolbar(
            selectedCount: selectedRSSURLs.count,
            visibleIDs: Set(filteredRSSSources.map(\.sourceUrl)),
            onSelect: { selectedRSSURLs = $0 },
            onEnable: { appState.sourceStore.setRSSEnabled(true, for: selectedRSSURLs); selectedRSSURLs.removeAll() },
            onDisable: { appState.sourceStore.setRSSEnabled(false, for: selectedRSSURLs); selectedRSSURLs.removeAll() },
            onDelete: { pendingDeleteRSSURLs = selectedRSSURLs }
        )
    }

    private func batchToolbar(
        selectedCount: Int,
        visibleIDs: Set<String>,
        onSelect: @escaping (Set<String>) -> Void,
        onEnable: @escaping () -> Void,
        onDisable: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("全选") { onSelect(visibleIDs) }
                Button("反选") { onSelect(visibleIDs.subtracting(currentSelectionForTab)) }
                Button("清空") { onSelect([]) }
                Spacer()
                Text("已选 \(selectedCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("启用", action: onEnable)
                Button("停用", action: onDisable)
                Button("删除", role: .destructive, action: onDelete)
            }
            .disabled(selectedCount == 0)
            .buttonStyle(.bordered)
        }
        .font(.subheadline.weight(.semibold))
        .padding(12)
        .background(AppTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var currentSelectionForTab: Set<String> {
        switch selectedTab {
        case .bookSources: return selectedBookSourceURLs
        case .catalogs: return selectedCatalogURLs
        case .rss: return selectedRSSURLs
        }
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

    private func selectableCatalogRow(_ catalog: SourceCatalog) -> some View {
        selectableSourceRow(
            id: catalog.url,
            title: catalog.name,
            subtitle: catalog.importUrl ?? catalog.url,
            enabled: catalog.enabled,
            badges: ["仓库", catalog.importedCount > 0 ? "已导入 \(catalog.importedCount)" : nil].compactMap { $0 },
            selected: selectedCatalogURLs.contains(catalog.url),
            onToggle: {
                if selectedCatalogURLs.contains(catalog.url) { selectedCatalogURLs.remove(catalog.url) }
                else { selectedCatalogURLs.insert(catalog.url) }
            }
        )
    }

    private func selectableRSSRow(_ source: RSSSource) -> some View {
        selectableSourceRow(
            id: source.sourceUrl,
            title: source.sourceName,
            subtitle: source.sourceUrl,
            enabled: source.enabled,
            badges: ["RSS", "文章"],
            selected: selectedRSSURLs.contains(source.sourceUrl),
            onToggle: {
                if selectedRSSURLs.contains(source.sourceUrl) { selectedRSSURLs.remove(source.sourceUrl) }
                else { selectedRSSURLs.insert(source.sourceUrl) }
            }
        )
    }

    private func selectableSourceRow(
        id: String,
        title: String,
        subtitle: String,
        enabled: Bool,
        badges: [String],
        selected: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AppTheme.accent : .secondary)
                    .frame(width: 32, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 8) {
                        statusBadge(enabled ? "启用" : "停用", color: enabled ? .green : .gray)
                        ForEach(badges, id: \.self) { statusBadge($0, color: .blue) }
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择 \(title)")
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
                Button("编辑 RSS") {
                    rssEditor = source
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
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        importMessage = "正在打开文件选择器..."
                        openFileImporterAfterSheetDismiss = true
                        showImportSheet = false
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

                if state.source.loginUrl?.nilIfEmpty != nil {
                    Button {
                        sourceLogin = state.source
                    } label: {
                        Label("先打开登录/验证页", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        UIPasteboard.general.string = sourceTest?.output ?? state.output ?? ""
                    }
                    .disabled((sourceTest?.output ?? state.output ?? "").isEmpty)
                }
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
                Text("将按顺序测试 \(state.sources.count) 个书源。默认会在搜索通过后继续验证首条结果的详情、目录和正文，避免只测搜索造成假绿。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("测试关键词", text: Binding(
                    get: { batchCheck?.keyword ?? state.keyword },
                    set: { batchCheck?.keyword = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)

                Toggle("搜索通过后深测首条结果", isOn: Binding(
                    get: { batchCheck?.deepCheckFirstResult ?? state.deepCheckFirstResult },
                    set: { batchCheck?.deepCheckFirstResult = $0 }
                ))
                .font(.subheadline.weight(.semibold))

                HStack {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

                if let current = batchCheck, current.hasResults {
                    HStack(spacing: 8) {
                        sourceCheckSummaryPill(title: "PASS", count: current.passedCount, color: .green)
                        sourceCheckSummaryPill(title: "WARN", count: current.warningCount, color: .orange)
                        sourceCheckSummaryPill(title: "FAIL", count: current.failedCount, color: .red)
                        sourceCheckSummaryPill(title: "LOGIN", count: current.loginRequiredCount, color: .orange)
                        sourceCheckSummaryPill(title: "VERIFY", count: current.verificationRequiredCount, color: .purple)
                        sourceCheckSummaryPill(title: "BLOCK", count: current.blockedCount, color: .red.opacity(0.8))
                        Spacer()
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        UIPasteboard.general.string = batchCheckExportText(batchCheck ?? state)
                    }
                    .disabled((batchCheck ?? state).results.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { batchCheck = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sourceCheckSummaryPill(title: String, count: Int, color: Color) -> some View {
        Text("\(title) \(count)")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func batchCheckExportText(_ state: SourceBatchCheckState) -> String {
        var lines = [
            "Source batch check",
            "keyword: \(state.keyword)",
            "checked: \(state.checkedCount)/\(state.sources.count)",
            "pass: \(state.passedCount), warn: \(state.warningCount), fail: \(state.failedCount), login: \(state.loginRequiredCount), verify: \(state.verificationRequiredCount), blocked: \(state.blockedCount)"
        ]
        for result in state.results {
            lines.append("")
            lines.append("[\(result.status.title)] \(result.sourceName)")
            lines.append("url: \(result.sourceURL)")
            lines.append("message: \(result.message)")
        }
        return lines.joined(separator: "\n")
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

        let engine = appState.engine
        var loginNote = ""
        if state.source.loginCheckJs?.nilIfEmpty != nil {
            let loginResult = await AsyncTimeout.run(seconds: 10) {
                await engine.verifyLogin(source: state.source)
            } ?? .failure(.network("Login check timed out"))
            switch loginResult {
            case .success(let verification):
                let health = verification.status.healthStatus
                loginNote = "\n[\(verification.status.displayTitle)] 登录检查：\(verification.message)（Cookie：\(verification.cookiePresent ? "present" : "absent")）"
                appState.sourceDiagnosticHistoryStore.record(
                    source: state.source,
                    stage: "login",
                    status: health,
                    message: verification.message,
                    resultCount: 0
                )
            case .failure(let error):
                loginNote = "\n[WARN] 登录检查失败：\(error.displayMessage)"
                appState.sourceDiagnosticHistoryStore.record(
                    source: state.source,
                    stage: "login",
                    status: .warning,
                    message: error.displayMessage,
                    resultCount: 0
                )
            }
        }
        let searchStartedAt = Date()
        let result = await AsyncTimeout.run(seconds: 10) {
            await engine.searchBooks(source: state.source, keyword: keyword, page: 1)
        } ?? .failure(.network("Search timed out"))
        guard var latest = sourceTest else { return }
        latest.isRunning = false
        switch result {
        case .success(let books):
            let preview = books.prefix(10).enumerated().map { index, book in
                "\(index + 1). \(book.name) | \(book.author ?? "未知作者")\n   \(book.bookUrl)"
            }.joined(separator: "\n")
            var output = sourceTestHeader(source: state.source, keyword: keyword) + loginNote
            output += "\n\n[PASS] 搜索：\(books.count) 条结果（\(elapsedMilliseconds(since: searchStartedAt))）"
            appState.sourceDiagnosticHistoryStore.record(
                source: state.source,
                stage: "search",
                status: books.isEmpty ? .warning : .passed,
                message: books.isEmpty ? "搜索请求成功但列表为空" : "搜索通过：\(books.count) 条结果",
                elapsedMilliseconds: Int(Date().timeIntervalSince(searchStartedAt) * 1_000),
                resultCount: books.count
            )
            if preview.isEmpty {
                output += "\n[WARN] 搜索请求成功但列表为空。建议检查 keyword/page 占位符、搜索规则列表选择器或接口返回结构。"
            } else {
                output += "\n\n\(preview)"
            }
            if let first = books.first {
                output += "\n\n正在验证首条结果详情..."
                latest.output = output
                sourceTest = latest
                let detailStartedAt = Date()
                let detailResult = await AsyncTimeout.run(seconds: 10) {
                    await engine.getBookDetail(source: state.source, book: first)
                } ?? .failure(.network("Detail test timed out"))
                switch detailResult {
                case .success(let detail):
                    output += "\n[PASS] 详情：\(detail.name)（\(elapsedMilliseconds(since: detailStartedAt))）"
                    let chapterStartedAt = Date()
                    let chapterResult = await AsyncTimeout.run(seconds: 10) {
                        await engine.getChapterList(source: state.source, book: detail)
                    } ?? .failure(.network("Chapter test timed out"))
                    switch chapterResult {
                    case .success(let chapters):
                        output += "\n[PASS] 目录：\(chapters.count) 章（\(elapsedMilliseconds(since: chapterStartedAt))）"
                        if let chapter = chapters.first {
                            let contentStartedAt = Date()
                            let contentResult = await AsyncTimeout.run(seconds: 10) {
                                await engine.getContent(source: state.source, chapter: chapter)
                            } ?? .failure(.network("Content test timed out"))
                            switch contentResult {
                            case .success(let content):
                                output += "\n[PASS] 正文：\(content.paragraphs.count) 段（\(elapsedMilliseconds(since: contentStartedAt))）"
                                appState.sourceDiagnosticHistoryStore.record(source: state.source, stage: "content", status: content.paragraphs.isEmpty ? .warning : .passed, message: "正文：\(content.paragraphs.count) 段", elapsedMilliseconds: Int(Date().timeIntervalSince(contentStartedAt) * 1_000), resultCount: content.paragraphs.count)
                                if content.paragraphs.isEmpty {
                                    output += "\n[WARN] 正文解析为空。建议检查 ruleContent.content / content 正则清洗是否过度。"
                                } else {
                                    output += "\n\n首段预览：\(content.paragraphs.first?.prefix(120) ?? "")"
                                }
                            case .failure(let error):
                                output += sourceTestFailure(stage: "正文", error: error)
                                appState.sourceDiagnosticHistoryStore.record(source: state.source, stage: "content", status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "content"), message: error.displayMessage, elapsedMilliseconds: Int(Date().timeIntervalSince(contentStartedAt) * 1_000))
                            }
                        } else {
                            output += "\n[WARN] 目录为空，无法验证正文。建议检查 ruleToc.chapterList / chapterName / chapterUrl。"
                        }
                    case .failure(let error):
                        output += sourceTestFailure(stage: "目录", error: error)
                        appState.sourceDiagnosticHistoryStore.record(source: state.source, stage: "toc", status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "toc"), message: error.displayMessage, elapsedMilliseconds: Int(Date().timeIntervalSince(chapterStartedAt) * 1_000))
                    }
                case .failure(let error):
                    output += sourceTestFailure(stage: "详情", error: error)
                    appState.sourceDiagnosticHistoryStore.record(source: state.source, stage: "detail", status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "detail"), message: error.displayMessage, elapsedMilliseconds: Int(Date().timeIntervalSince(detailStartedAt) * 1_000))
                }
            }
            latest.output = output
        case .failure(let error):
            latest.output = sourceTestHeader(source: state.source, keyword: keyword) + loginNote
                + sourceTestFailure(stage: "搜索", error: error)
            appState.sourceDiagnosticHistoryStore.record(source: state.source, stage: "search", status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "search"), message: error.displayMessage, elapsedMilliseconds: Int(Date().timeIntervalSince(searchStartedAt) * 1_000))
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

        let engine = appState.engine
        for source in state.sources {
            var loginMessage = ""
            if source.loginCheckJs?.nilIfEmpty != nil {
                let loginResult = await AsyncTimeout.run(seconds: 10) {
                    await engine.verifyLogin(source: source)
                } ?? .failure(.network("Login check timed out"))
                switch loginResult {
                case .success(let verification):
                    loginMessage = "登录检查：\(verification.message)"
                    appState.sourceDiagnosticHistoryStore.record(source: source, stage: "batch.login", status: verification.status.healthStatus, message: verification.message)
                case .failure(let error):
                    loginMessage = "登录检查失败：\(error.displayMessage)"
                    appState.sourceDiagnosticHistoryStore.record(source: source, stage: "batch.login", status: .warning, message: error.displayMessage)
                }
            }
            let result = await AsyncTimeout.run(seconds: 10) {
                await engine.searchBooks(source: source, keyword: keyword, page: 1)
            } ?? .failure(.network("Search timed out"))
            guard var latest = batchCheck else { return }
            latest.checkedCount += 1
            switch result {
            case .success(let books):
                var status: SourceBatchCheckStatus = books.isEmpty ? .warning : .passed
                var message = books.isEmpty
                    ? "搜索请求成功但结果为空，优先检查 searchUrl、分页占位符和 ruleSearch.bookList。"
                    : "搜索通过：\(books.count) 条结果。"
                if !loginMessage.isEmpty { message += " \(loginMessage)" }
                if state.deepCheckFirstResult, let first = books.first {
                    let deep = await batchDeepCheckFirstResult(source: source, book: first)
                    status = deep.status
                    message += " \(deep.message)"
                }
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
                appState.sourceDiagnosticHistoryStore.record(
                    source: source,
                    stage: "batch.search",
                    status: status.healthStatus,
                    message: message,
                    resultCount: books.count
                )
            case .failure(let error):
                var message = "\(error.displayMessage)；建议：\(sourceTestAdvice(stage: "搜索", error: error))"
                if !loginMessage.isEmpty { message += " \(loginMessage)" }
                let classified = SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "search")
                latest.results.append(
                    SourceBatchCheckResult(
                        sourceName: source.bookSourceName,
                        sourceURL: source.bookSourceUrl,
                        status: SourceBatchCheckStatus(classified),
                        message: message
                    )
                )
                appState.sourceHealthStore.record(
                    source: source,
                    status: classified,
                    message: message,
                    keyword: keyword,
                    resultCount: 0
                )
                appState.sourceDiagnosticHistoryStore.record(
                    source: source,
                    stage: "batch.search",
                    status: classified,
                    message: message
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

    private func elapsedMilliseconds(since startedAt: Date) -> String {
        let milliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        return "耗时 \(milliseconds) ms"
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

    private func batchDeepCheckFirstResult(source: BookSource, book: SearchBook) async -> (status: SourceBatchCheckStatus, message: String) {
        let engine = appState.engine
        let detailResult = await AsyncTimeout.run(seconds: 10) {
            await engine.getBookDetail(source: source, book: book)
        } ?? .failure(.network("Detail deep check timed out"))
        switch detailResult {
        case .success(let detail):
            let chapterResult = await AsyncTimeout.run(seconds: 10) {
                await engine.getChapterList(source: source, book: detail)
            } ?? .failure(.network("Chapter deep check timed out"))
            switch chapterResult {
            case .success(let chapters):
                guard let firstChapter = chapters.first else {
                    return (.warning, "深测：详情通过，但目录为空。")
                }
                let contentResult = await AsyncTimeout.run(seconds: 10) {
                    await engine.getContent(source: source, chapter: firstChapter)
                } ?? .failure(.network("Content deep check timed out"))
                switch contentResult {
                case .success(let content):
                    if content.paragraphs.isEmpty {
                        return (.warning, "深测：详情/目录通过，但正文为空。")
                    }
                    return (.passed, "深测通过：详情/目录/正文均可用，正文 \(content.paragraphs.count) 段。")
                case .failure(let error):
                    return (SourceBatchCheckStatus(SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "content")), "深测正文失败：\(error.displayMessage)")
                }
            case .failure(let error):
                return (SourceBatchCheckStatus(SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "toc")), "深测目录失败：\(error.displayMessage)")
            }
        case .failure(let error):
            return (SourceBatchCheckStatus(SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "detail")), "深测详情失败：\(error.displayMessage)")
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
            guard let url = try result.get().first else {
                importMessage = nil
                importError = "导入失败：没有选择文件。"
                return
            }
            let file = try PickedDocumentAccess.data(from: url)
            let data = file.data
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

private struct SourceVisualDetailView: View {
    @EnvironmentObject private var appState: AppState
    let source: BookSource
    let health: SourceHealthRecord?
    let onTest: () -> Void
    let onEditRules: () -> Void
    let onEditJSON: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticKeyword = "斗破苍穹"
    @State private var dynamicResults: [SourceVisualDiagnosticStage] = []
    @State private var isRunningDiagnostic = false

    private var stages: [(String, String, String, Bool)] {
        [
            ("搜索", "searchUrl", "magnifyingglass", source.searchUrl?.nilIfEmpty != nil && source.ruleSearch != nil),
            ("详情", "ruleBookInfo", "doc.text.magnifyingglass", source.ruleBookInfo != nil),
            ("目录", "ruleToc", "list.bullet.rectangle", source.ruleToc != nil),
            ("正文", "ruleContent", "book.pages", source.ruleContent != nil)
        ]
    }

    private var latestDiagnostics: [String: SourceDiagnosticHistoryRecord] {
        var result: [String: SourceDiagnosticHistoryRecord] = [:]
        for record in appState.sourceDiagnosticHistoryStore.records(for: source) {
            let stage = record.stage.lowercased()
            for key in ["search", "detail", "toc", "content"]
            where stage == key || stage.hasSuffix(".\(key)") {
                if result[key] == nil { result[key] = record }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(source.bookSourceName).font(.title2.bold())
                        Text(source.bookSourceUrl).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack(spacing: 8) {
                            statusPill(source.enabled ? "启用" : "停用", color: source.enabled ? .green : .gray)
                            if let health { statusPill(health.status.title, color: health.status.color) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .podcastCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("可视化链路").font(.headline)
                        ForEach(stages, id: \.1) { stage in
                            HStack(spacing: 12) {
                                Image(systemName: stage.2)
                                    .frame(width: 28)
                                    .foregroundStyle(stage.3 ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stage.0).font(.subheadline.weight(.semibold))
                                    Text(stage.1).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: stage.3 ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(stage.3 ? .green : .secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .podcastCard()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最近一次动态诊断").font(.headline)
                            Spacer()
                            Text(latestDiagnostics.isEmpty ? "未运行" : "按阶段记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TextField("诊断关键词", text: $diagnosticKeyword)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                        Button {
                            runDynamicDiagnostic()
                        } label: {
                            HStack {
                                Label(isRunningDiagnostic ? "诊断中…" : "运行 Search → Detail → TOC → Content", systemImage: "play.circle.fill")
                                Spacer()
                                if isRunningDiagnostic { ProgressView().controlSize(.small) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunningDiagnostic || diagnosticKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if dynamicResults.isEmpty {
                            ForEach(stages, id: \.1) { stage in
                                diagnosticResultRow(stageKey: stage.1, title: stage.0, icon: stage.2)
                            }
                        } else {
                            ForEach(dynamicResults) { result in
                                dynamicDiagnosticResultRow(result)
                            }
                        }
                    }
                    .podcastCard()

                    VStack(spacing: 10) {
                        Button { dismiss(); onTest() } label: {
                            Label("运行全链路测试", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button { dismiss(); onEditRules() } label: {
                            Label("编辑规则", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button { dismiss(); onEditJSON() } label: {
                            Label("编辑 JSON", systemImage: "curlybraces").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .pageBackground()
            .navigationTitle("书源详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func statusPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private func diagnosticResultRow(stageKey: String, title: String, icon: String) -> some View {
        let record = latestDiagnostics[stageKey]
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: record?.status.systemImage ?? icon)
                .foregroundStyle(record?.status.color ?? .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let record {
                        Text(record.status.shortTitle)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(record.status.color)
                        if let elapsed = record.elapsedMilliseconds {
                            Text("\u{00b7} \(elapsed) ms").font(.caption2).foregroundStyle(.secondary)
                        }
                        if record.resultCount > 0 {
                            Text("\u{00b7} \(record.resultCount) \u{6761}").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\u{5f85}\u{8fd0}\u{884c}").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(record?.message ?? "\u{8fd0}\u{884c}\u{5168}\u{94fe}\u{8def}\u{6d4b}\u{8bd5}\u{540e}\u{663e}\u{793a}\u{771f}\u{5b9e}\u{8bf7}\u{6c42}\u{3001}\u{89e3}\u{6790}\u{548c}\u{5931}\u{8d25}\u{5efa}\u{8bae}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func dynamicDiagnosticResultRow(_ result: SourceVisualDiagnosticStage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.status.systemImage)
                .foregroundStyle(result.status.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.title).font(.subheadline.weight(.semibold))
                    Text(result.status.shortTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(result.status.color)
                    Text("· \(result.elapsedMilliseconds) ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if result.resultCount > 0 {
                        Text("· \(result.resultCount) 条")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func runDynamicDiagnostic() {
        guard !isRunningDiagnostic else { return }
        let keyword = diagnosticKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isRunningDiagnostic = true
        dynamicResults = []
        Task { @MainActor in
            await executeDynamicDiagnostic(keyword: keyword)
            isRunningDiagnostic = false
        }
    }

    @MainActor
    private func executeDynamicDiagnostic(keyword: String) async {
        let engine = appState.engine

        func elapsed(_ startedAt: Date) -> Int {
            max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        }

        func appendResult(
            key: String,
            title: String,
            status: SourceHealthStatus,
            message: String,
            milliseconds: Int,
            count: Int = 0
        ) {
            dynamicResults.append(SourceVisualDiagnosticStage(
                key: key,
                title: title,
                status: status,
                message: message,
                elapsedMilliseconds: milliseconds,
                resultCount: count
            ))
            appState.sourceDiagnosticHistoryStore.record(
                source: source,
                stage: key,
                status: status,
                message: message,
                elapsedMilliseconds: milliseconds,
                resultCount: count
            )
        }

        let searchStartedAt = Date()
        let search = await AsyncTimeout.run(seconds: 10) {
            await engine.searchBooks(source: source, keyword: keyword, page: 1)
        } ?? .failure(.network("Search timed out"))
        switch search {
        case .failure(let error):
            let status = SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "search")
            appendResult(key: "search", title: "搜索", status: status, message: error.displayMessage, milliseconds: elapsed(searchStartedAt))
            return
        case .success(let books):
            let status: SourceHealthStatus = books.isEmpty ? .warning : .passed
            appendResult(
                key: "search",
                title: "搜索",
                status: status,
                message: books.isEmpty ? "请求成功但结果为空；检查搜索规则和分页占位符。" : "搜索通过：\(books.count) 条结果。",
                milliseconds: elapsed(searchStartedAt),
                count: books.count
            )
            guard let first = books.first else { return }

            let detailStartedAt = Date()
            let detail = await AsyncTimeout.run(seconds: 10) {
                await engine.getBookDetail(source: source, book: first)
            } ?? .failure(.network("Detail timed out"))
            switch detail {
            case .failure(let error):
                appendResult(key: "detail", title: "详情", status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "detail"), message: error.displayMessage, milliseconds: elapsed(detailStartedAt))
                return
            case .success(let book):
                appendResult(key: "detail", title: "详情", status: .passed, message: "详情通过：\(book.name)", milliseconds: elapsed(detailStartedAt), count: 1)

                let tocStartedAt = Date()
                let toc = await AsyncTimeout.run(seconds: 10) {
                    await engine.getChapterList(source: source, book: book)
                } ?? .failure(.network("TOC timed out"))
                switch toc {
                case .failure(let error):
                    appendResult(key: "toc", title: "目录", status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "toc"), message: error.displayMessage, milliseconds: elapsed(tocStartedAt))
                    return
                case .success(let chapters):
                    let tocStatus: SourceHealthStatus = chapters.isEmpty ? .warning : .passed
                    appendResult(key: "toc", title: "目录", status: tocStatus, message: chapters.isEmpty ? "目录为空；检查 chapterList/chapterUrl。" : "目录通过：\(chapters.count) 章。", milliseconds: elapsed(tocStartedAt), count: chapters.count)
                    guard let firstChapter = chapters.first else { return }

                    let contentStartedAt = Date()
                    let content = await AsyncTimeout.run(seconds: 10) {
                        await engine.getContent(source: source, chapter: firstChapter)
                    } ?? .failure(.network("Content timed out"))
                    switch content {
                    case .failure(let error):
                        appendResult(key: "content", title: "正文", status: SourceDiagnosticClassifier.status(message: error.displayMessage, stage: "content"), message: error.displayMessage, milliseconds: elapsed(contentStartedAt))
                    case .success(let chapterContent):
                        let contentStatus: SourceHealthStatus = chapterContent.paragraphs.isEmpty ? .warning : .passed
                        appendResult(key: "content", title: "正文", status: contentStatus, message: chapterContent.paragraphs.isEmpty ? "正文为空；检查 ruleContent.content 和净化规则。" : "正文通过：\(chapterContent.paragraphs.count) 段。", milliseconds: elapsed(contentStartedAt), count: chapterContent.paragraphs.count)
                    }
                }
            }
        }
    }
}

private struct SourceVisualDiagnosticStage: Identifiable {
    let id = UUID()
    let key: String
    let title: String
    let status: SourceHealthStatus
    let message: String
    let elapsedMilliseconds: Int
    let resultCount: Int
}

private struct SourceTestState: Identifiable, Sendable {
    let id = UUID()
    let source: BookSource
    var keyword = "斗破苍穹"
    var isRunning = false
    var output: String?
}

private struct SourceBatchCheckState: Identifiable, Sendable {
    let id = UUID()
    let sources: [BookSource]
    var keyword = "斗破苍穹"
    var deepCheckFirstResult = true
    var isRunning = false
    var checkedCount = 0
    var results: [SourceBatchCheckResult] = []

    var hasResults: Bool { !results.isEmpty }
    var passedCount: Int { results.filter { $0.status == .passed }.count }
    var warningCount: Int { results.filter { $0.status == .warning }.count }
    var failedCount: Int { results.filter { $0.status == .failed }.count }
    var loginRequiredCount: Int { results.filter { $0.status == .requiresLogin }.count }
    var verificationRequiredCount: Int { results.filter { $0.status == .verificationRequired }.count }
    var blockedCount: Int { results.filter { $0.status == .blocked }.count }
}

private struct SourceBatchCheckResult: Identifiable, Sendable {
    let id = UUID()
    let sourceName: String
    let sourceURL: String
    let status: SourceBatchCheckStatus
    let message: String
}

private extension SourceHealthStatus {
    var shortTitle: String {
        switch self {
        case .passed: return "PASS"
        case .warning: return "WARN"
        case .failed: return "FAIL"
        case .requiresLogin: return "LOGIN"
        case .verificationRequired: return "VERIFY"
        case .blocked: return "BLOCK"
        }
    }

    var title: String {
        switch self {
        case .passed: return "上次通过"
        case .warning: return "上次警告"
        case .failed: return "上次失败"
        case .requiresLogin: return "需要登录"
        case .verificationRequired: return "需要验证"
        case .blocked: return "被拦截"
        }
    }

    var systemImage: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .requiresLogin: return "person.crop.circle.badge.exclamationmark"
        case .verificationRequired: return "shield.lefthalf.filled.badge.exclamationmark"
        case .blocked: return "hand.raised.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        case .requiresLogin: return .orange
        case .verificationRequired: return .purple
        case .blocked: return .red.opacity(0.8)
        }
    }
}

private enum SourceBatchCheckStatus: Equatable, Sendable {
    case passed
    case warning
    case failed
    case requiresLogin
    case verificationRequired
    case blocked

    init(_ status: SourceHealthStatus) {
        switch status {
        case .passed: self = .passed
        case .warning: self = .warning
        case .failed: self = .failed
        case .requiresLogin: self = .requiresLogin
        case .verificationRequired: self = .verificationRequired
        case .blocked: self = .blocked
        }
    }

    var healthStatus: SourceHealthStatus {
        switch self {
        case .passed: return .passed
        case .warning: return .warning
        case .failed: return .failed
        case .requiresLogin: return .requiresLogin
        case .verificationRequired: return .verificationRequired
        case .blocked: return .blocked
        }
    }

    var title: String {
        switch self {
        case .passed: return "PASS"
        case .warning: return "WARN"
        case .failed: return "FAIL"
        case .requiresLogin: return "LOGIN"
        case .verificationRequired: return "VERIFY"
        case .blocked: return "BLOCKED"
        }
    }

    var systemImage: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .requiresLogin: return "person.crop.circle.badge.exclamationmark"
        case .verificationRequired: return "shield.lefthalf.filled.badge.exclamationmark"
        case .blocked: return "hand.raised.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        case .requiresLogin: return .orange
        case .verificationRequired: return .purple
        case .blocked: return .red.opacity(0.8)
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
