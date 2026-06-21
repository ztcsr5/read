import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SourceManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: SourceManagerTab = .bookSources
    @State private var isManaging = false
    @State private var searchText = ""
    @State private var selectedSourceURLs = Set<String>()
    @State private var importText = ""
    @State private var importURL = ""
    @State private var importError: String?
    @State private var importMessage: String?
    @State private var showFileImporter = false
    @State private var showImportSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showUnavailableNotice = false

    private var filteredSources: [BookSource] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return appState.sourceStore.sources }
        return appState.sourceStore.sources.filter { source in
            let values = [
                source.bookSourceName,
                source.bookSourceUrl,
                source.bookSourceGroup ?? "",
                source.searchUrl ?? ""
            ]
            return values.contains { $0.lowercased().contains(keyword) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    webServiceCard
                    tabPicker

                    if selectedTab == .bookSources {
                        bookSourceContent
                    } else {
                        unavailableTabContent
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 10)
            }
            .pageBackground()
            .navigationTitle("源管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !appState.sourceStore.sources.isEmpty {
                        Button(isManaging ? "完成" : "管理") {
                            isManaging.toggle()
                            if !isManaging {
                                selectedSourceURLs.removeAll()
                            }
                        }
                    }

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
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
            .confirmationDialog("确定删除选中的书源吗？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    appState.sourceStore.remove(sourceURLs: selectedSourceURLs)
                    selectedSourceURLs.removeAll()
                    isManaging = false
                }
                Button("取消", role: .cancel) {}
            }
            .alert("功能正在恢复", isPresented: $showUnavailableNotice) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("仓库、RSS、Web 写源和完整测源会按 Flutter 原版继续补齐；当前阶段先保证书源导入、搜索、启停和删除可用。")
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

            Text("Flutter 版的本地网页编辑服务会在后续阶段恢复。当前请先通过粘贴、文件或 URL 导入书源 JSON。")
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
            selectedSourceURLs.removeAll()
            isManaging = false
        }
    }

    private var bookSourceContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !appState.sourceStore.sources.isEmpty {
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

            if isManaging && !filteredSources.isEmpty {
                manageBar
            }

            if appState.sourceStore.sources.isEmpty {
                EmptyStateCard(
                    systemImage: "tray",
                    title: "暂无书源",
                    message: "请点击右上角 + 导入书源 JSON"
                )
            } else if filteredSources.isEmpty {
                CenterTextEmptyState("没有匹配的结果", minHeight: 220)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredSources) { source in
                        sourceRow(source)
                    }
                }
            }

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
    }

    private var manageBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("已选 \(selectedSourceURLs.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                smallAction("全选") {
                    selectedSourceURLs = Set(filteredSources.map(\.bookSourceUrl))
                }

                smallAction("反选") {
                    let visible = Set(filteredSources.map(\.bookSourceUrl))
                    selectedSourceURLs = visible.subtracting(selectedSourceURLs)
                }

                smallAction("测源") {
                    showUnavailableNotice = true
                }

                smallAction("启用", disabled: selectedSourceURLs.isEmpty) {
                    appState.sourceStore.setEnabled(true, for: selectedSourceURLs)
                }

                smallAction("停用", disabled: selectedSourceURLs.isEmpty) {
                    appState.sourceStore.setEnabled(false, for: selectedSourceURLs)
                }

                smallAction("删除", destructive: true, disabled: selectedSourceURLs.isEmpty) {
                    showDeleteConfirmation = true
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func smallAction(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(destructive ? Color.red : Color.blue)
                .background((destructive ? Color.red : Color.blue).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func sourceRow(_ source: BookSource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if isManaging {
                Button {
                    toggleSelection(source)
                } label: {
                    Image(systemName: selectedSourceURLs.contains(source.bookSourceUrl) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedSourceURLs.contains(source.bookSourceUrl) ? AppTheme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(source.bookSourceName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text([source.bookSourceUrl, source.bookSourceGroup].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(source.enabled ? "启用" : "停用")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(source.enabled ? .green : .secondary)
                        .background((source.enabled ? Color.green : Color.gray).opacity(0.14))
                        .clipShape(Capsule())

                    if source.ruleSearch != nil {
                        Text("可搜索")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(.blue)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if !isManaging {
                Menu {
                    Button(source.enabled ? "停用" : "启用") {
                        appState.sourceStore.setEnabled(!source.enabled, for: [source.bookSourceUrl])
                    }
                    Button("测试书源") {
                        showUnavailableNotice = true
                    }
                    Button("查看 JSON") {
                        showUnavailableNotice = true
                    }
                    Button("删除", role: .destructive) {
                        appState.sourceStore.remove(source)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(14)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if isManaging {
                toggleSelection(source)
            }
        }
    }

    private var unavailableTabContent: some View {
        VStack(spacing: 16) {
            EmptyStateCard(
                systemImage: selectedTab == .catalogs ? "square.stack" : "newspaper",
                title: selectedTab == .catalogs ? "暂无书源仓库" : "暂无 RSS",
                message: selectedTab == .catalogs
                    ? "仓库订阅会按 Flutter 原版继续恢复。"
                    : "普通文章订阅会按 Flutter 原版继续恢复。"
            )

            Button("导入源数据") {
                showImportSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("支持书源 JSON、仓库订阅 JSON、RSS/Atom、阅读导入链接和网页分享入口。大文件建议选择本地 JSON。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("书源 JSON URL，可选", text: $importURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 230)
                    .overlay(alignment: .topLeading) {
                        if importText.isEmpty {
                            Text("粘贴 JSON、HTTP 地址、分享页或 yuedu:// 链接")
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
                        importSources()
                    } label: {
                        Label("自动识别并导入", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)

                if let importMessage {
                    Text(importMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                }

                if let importError {
                    Text(importError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)
            }
            .padding(.top)
            .navigationTitle("导入源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showImportSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        importSources()
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func toggleSelection(_ source: BookSource) {
        if selectedSourceURLs.contains(source.bookSourceUrl) {
            selectedSourceURLs.remove(source.bookSourceUrl)
        } else {
            selectedSourceURLs.insert(source.bookSourceUrl)
        }
    }

    private func importSources() {
        do {
            let before = appState.sourceStore.sources.count
            try appState.sourceStore.importJSON(importText)
            let total = appState.sourceStore.sources.count
            importText = ""
            importError = nil
            importMessage = "导入成功，当前 \(total) 个源，新增/更新 \(max(0, total - before)) 个源"
            showImportSheet = false
        } catch {
            importMessage = nil
            importError = error.localizedDescription
        }
    }

    private func pasteFromClipboard() {
        importText = UIPasteboard.general.string ?? ""
        importMessage = importText.isEmpty ? nil : "已从剪贴板粘贴"
        importError = importText.isEmpty ? "剪贴板没有文本" : nil
    }

    private func importFromURL() async {
        do {
            let text = importURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: text) else {
                importError = "URL 无效"
                return
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = ResponseTextDecoder().decode(data: data, headers: [:])
            let before = appState.sourceStore.sources.count
            try appState.sourceStore.importJSON(decoded)
            let total = appState.sourceStore.sources.count
            importURL = ""
            importError = nil
            importMessage = "URL 导入成功，当前 \(total) 个源，新增/更新 \(max(0, total - before)) 个源"
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
            let before = appState.sourceStore.sources.count
            try appState.sourceStore.importJSON(text)
            let total = appState.sourceStore.sources.count
            importError = nil
            importMessage = "文件导入成功，当前 \(total) 个源，新增/更新 \(max(0, total - before)) 个源"
        } catch {
            importMessage = nil
            importError = error.localizedDescription
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
