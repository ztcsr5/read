import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @State private var cacheSize = "无缓存"

    private var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRawValue) ?? .system }
        set { themeModeRawValue = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("外观") {
                    ForEach(ThemeMode.allCases) { mode in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            themeModeRawValue = mode.rawValue
                        } label: {
                            HStack {
                                Text(mode.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if themeMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                    }
                }

                Section("内容设置") {
                    NavigationLink {
                        SourceManagerView()
                    } label: {
                        Label("书源管理", systemImage: "square.stack.3d.up")
                    }

                    NavigationLink {
                        SourceWritingView(server: appState.sourceWritingServer)
                    } label: {
                        Label("Web 写源", systemImage: "network")
                    }

                    NavigationLink {
                        RuleHealthView()
                    } label: {
                        Label("规则体检", systemImage: "shield")
                    }

                    NavigationLink {
                        PurifyRulesView()
                    } label: {
                        Label("净化规则", systemImage: "wand.and.stars")
                    }
                }

                Section("通用") {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        appState.chapterContentCacheStore.removeAll()
                        updateCacheSummary()
                    } label: {
                        HStack {
                            Label("清理章节缓存", systemImage: "trash")
                            Spacer()
                            Text(cacheSize)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        ReadingHistoryView()
                    } label: {
                        Label("阅读历史", systemImage: "clock")
                    }

                    NavigationLink {
                        ReadingStatsView()
                    } label: {
                        Label("阅读统计", systemImage: "chart.bar.xaxis")
                    }

                    NavigationLink {
                        AboutReadView()
                    } label: {
                        Label("关于阅读", systemImage: "info.circle")
                    }
                }

                Section("最近诊断") {
                    if appState.diagnostics.isEmpty {
                        Text("暂无诊断")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            UIPasteboard.general.string = diagnosticExportText(events: appState.diagnostics)
                        } label: {
                            Label("Copy all diagnostics", systemImage: "doc.on.doc")
                        }

                        ForEach(Array(appState.diagnostics.prefix(12))) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("[\(event.stage)] \(event.message)")
                                    .font(.subheadline.weight(.semibold))
                                if let sourceName = event.sourceName {
                                    Text(sourceName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(event.details.sorted(by: { $0.key < $1.key }), id: \.key) { item in
                                    Text("\(item.key): \(item.value)")
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .pageBackground()
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .onAppear {
                updateCacheSummary()
                appState.chapterContentCacheStore.removeExpired()
                updateCacheSummary()
            }
        }
    }

    private func updateCacheSummary() {
        let chapters = appState.chapterContentCacheStore.entries.count
        cacheSize = chapters == 0
            ? "无缓存"
            : "\(chapters) 章 / \(byteCountText(appState.chapterContentCacheStore.estimatedByteCount))"
    }

    private func byteCountText(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    private func diagnosticExportText(events: [DiagnosticEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        return events.prefix(200).map { event in
            var lines = [
                "[\(event.level.rawValue.uppercased())] \(formatter.string(from: event.date))",
                "stage: \(event.stage)",
                "message: \(event.message)"
            ]
            if let sourceName = event.sourceName {
                lines.append("source: \(sourceName)")
            }
            for item in event.details.sorted(by: { $0.key < $1.key }) {
                lines.append("\(item.key): \(item.value)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n---\n\n")
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case eyeCare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        case .eyeCare: return "护眼模式"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .eyeCare: return .light
        case .dark: return .dark
        }
    }
}

struct ReadingHistoryView: View {
    @EnvironmentObject private var appState: AppState

    private var books: [BookshelfBook] {
        appState.bookshelfStore.books.sorted {
            ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt)
        }
    }

    var body: some View {
        List {
            if books.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("暂无阅读历史")
                        .font(.headline)
                    Text("从发现页加入书架或导入 TXT 后，阅读记录会显示在这里。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            } else {
                ForEach(books) { book in
                    NavigationLink {
                        BookshelfReaderGatewayView(book: book)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(book.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(book.readingProgress * 100))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                            Text(book.currentChapterTitle ?? book.latestChapterTitle ?? "尚未开始")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 10) {
                                Label("\(book.readingSessionCount ?? 0) 次", systemImage: "book")
                                Label(readingDurationText(book.totalReadingSeconds ?? 0), systemImage: "timer")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let lastReadAt = book.lastReadAt {
                                Text(lastReadAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            appState.bookshelfStore.remove(bookID: book.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("阅读历史")
    }

    private func readingDurationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "少于 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        return String(format: "%.1f 小时", Double(minutes) / 60.0)
    }
}

struct ReadingStatsView: View {
    @EnvironmentObject private var appState: AppState

    private var summary: ReadingStatsSummary {
        ReadingStatsSummary(books: appState.bookshelfStore.books)
    }

    var body: some View {
        List {
            if summary.totalBooks == 0 {
                emptyState
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("阅读概览")
                            .font(.headline)
                        HStack(spacing: 12) {
                            statCard("总时长", value: durationText(summary.totalReadingSeconds), icon: "timer")
                            statCard("阅读次数", value: "\(summary.totalSessions)", icon: "book")
                        }
                        HStack(spacing: 12) {
                            statCard("平均进度", value: "\(Int(summary.averageProgress * 100))%", icon: "chart.line.uptrend.xyaxis")
                            statCard("书签", value: "\(summary.totalBookmarks)", icon: "bookmark")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("书架构成") {
                    metricRow("书架书籍", value: "\(summary.totalBooks)")
                    metricRow("在线书籍", value: "\(summary.remoteBooks)")
                    metricRow("本地导入", value: "\(summary.localBooks)")
                    metricRow("已阅读", value: "\(summary.readBooks)")
                    metricRow("有书签", value: "\(summary.bookmarkedBooks)")
                }

                if let mostReadBook = summary.mostReadBook {
                    Section("阅读最多") {
                        NavigationLink {
                            BookshelfReaderGatewayView(book: mostReadBook)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(mostReadBook.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("\(durationText(mostReadBook.totalReadingSeconds ?? 0)) / \(mostReadBook.readingSessionCount ?? 0) 次")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("最近阅读") {
                    ForEach(summary.recentBooks) { book in
                        NavigationLink {
                            BookshelfReaderGatewayView(book: book)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(book.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(book.readingProgress * 100))%")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                                if let lastReadAt = book.lastReadAt {
                                    Text(lastReadAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("阅读统计")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text("暂无统计")
                .font(.headline)
            Text("打开书籍阅读后，这里会汇总阅读时长、次数、进度和书签。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private func statCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "少于 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        return String(format: "%.1f 小时", Double(minutes) / 60.0)
    }
}

private struct RuleHealthView: View {
    @EnvironmentObject private var appState: AppState

    private var sourceStats: RuleHealthStats {
        RuleHealthStats(sources: appState.sourceStore.sources)
    }

    var body: some View {
        List {
            Section("总览") {
                metricRow("书源总数", value: "\(sourceStats.total)")
                metricRow("启用书源", value: "\(sourceStats.enabled)")
                metricRow("可搜索", value: "\(sourceStats.searchable)")
                metricRow("可读正文", value: "\(sourceStats.readable)")
            }

            Section("需要处理") {
                if sourceStats.problemSources.isEmpty {
                    Label("当前未发现明显规则缺失", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(sourceStats.problemSources) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(source.bookSourceName)
                                .font(.headline)
                            Text(source.bookSourceUrl)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(problemText(for: source))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section("说明") {
                Text("这里先做本地规则体检：识别缺 searchUrl、目录规则、正文规则的源。后续再补自动净化、规则迁移和批量修复。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("规则体检")
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func problemText(for source: BookSource) -> String {
        var problems: [String] = []
        if source.searchUrl?.isEmpty ?? true {
            problems.append("缺搜索地址")
        }
        if source.ruleToc == nil {
            problems.append("缺目录规则")
        }
        if source.ruleContent == nil {
            problems.append("缺正文规则")
        }
        return problems.joined(separator: " / ")
    }
}

private struct PurifyRulesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newRule = ""
    @State private var importText = ""
    @State private var importUrl = ""
    @State private var selectedPresetIDs: Set<String> = []
    @State private var previewText = "正文第一段\n请收藏本站，最新网址 example.com\n广告内容"
    @State private var message: String?
    @State private var urlMessage: String?
    @State private var isDownloadingRules = false

    var body: some View {
        List {
            Section("新增规则") {
                TextField("正则或 规则##替换文本", text: $newRule)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("添加") {
                    appState.purifyRuleStore.add(newRule)
                    newRule = ""
                }
                .disabled(newRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("批量导入") {
                TextEditor(text: $importText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 120)
                Button("按行导入") {
                    let count = appState.purifyRuleStore.importLines(importText)
                    importText = ""
                    message = "已导入 \(count) 条净化规则"
                }
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("URL 导入") {
                TextField("请输入净化规则的 URL 地址", text: $importUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button(isDownloadingRules ? "正在下载..." : "从 URL 导入") {
                    Task { await importRulesFromUrl() }
                }
                .disabled(importUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDownloadingRules)
                if let urlMessage {
                    Text(urlMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("推荐预设") {
                Text("预设只作为起点导入，后续仍可逐条关闭或删除。导入会自动跳过已存在规则。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(PurifyRulePreset.builtIn) { preset in
                    let isFullyImported = preset.patterns.allSatisfy {
                        appState.purifyRuleStore.containsPattern($0)
                    }
                    Toggle(isOn: Binding(
                        get: { selectedPresetIDs.contains(preset.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedPresetIDs.insert(preset.id)
                            } else {
                                selectedPresetIDs.remove(preset.id)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(preset.title)
                                if isFullyImported {
                                    Text("已导入")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(preset.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isFullyImported)
                }

                Button("导入选中预设") {
                    let imported = appState.purifyRuleStore.importPatterns(selectedPresetPatterns)
                    selectedPresetIDs.removeAll()
                    message = "已导入 \(imported) 条预设规则"
                }
                .disabled(selectedPresetPatterns.isEmpty)
            }

            Section("快速管理") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(appState.purifyRuleStore.enabledPatterns.count) / \(appState.purifyRuleStore.rules.count) 条启用")
                        Text("关闭规则会保留内容，便于排查误删正文。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Button("启用全部") {
                        appState.purifyRuleStore.setAllEnabled(true)
                    }
                    .disabled(appState.purifyRuleStore.rules.isEmpty)

                    Button("停用全部") {
                        appState.purifyRuleStore.setAllEnabled(false)
                    }
                    .disabled(appState.purifyRuleStore.rules.isEmpty)
                }
            }

            Section("规则测试") {
                TextEditor(text: $previewText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 90)
                VStack(alignment: .leading, spacing: 6) {
                    Text("净化结果")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(appState.purifyRuleStore.preview(text: previewText))
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            Section("已启用规则") {
                if appState.purifyRuleStore.rules.isEmpty {
                    Text("暂无净化规则。规则会在正文解析后执行，用于删除广告、站点尾巴或固定乱码片段。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.purifyRuleStore.rules) { rule in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { rule.enabled },
                                set: { appState.purifyRuleStore.setEnabled($0, ruleID: rule.id) }
                            )) {
                                Text(rule.pattern)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(3)
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                appState.purifyRuleStore.remove(ruleID: rule.id)
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { dismissKeyboard() }
            }
        }
        .navigationTitle("净化规则")
    }

    private var selectedPresetPatterns: [String] {
        PurifyRulePreset.builtIn
            .filter { selectedPresetIDs.contains($0.id) }
            .flatMap(\.patterns)
            .filter { !appState.purifyRuleStore.containsPattern($0) }
    }

    private func importRulesFromUrl() async {
        let trimmed = importUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            urlMessage = "无效的 URL 地址"
            return
        }

        isDownloadingRules = true
        urlMessage = "正在拉取规则..."

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                isDownloadingRules = false
                urlMessage = "下载失败：服务器响应错误"
                return
            }

            guard let text = String(data: data, encoding: .utf8) else {
                isDownloadingRules = false
                urlMessage = "解码失败：内容不是有效的 UTF-8 文本"
                return
            }

            let count = appState.purifyRuleStore.importLines(text)
            importUrl = ""
            isDownloadingRules = false
            urlMessage = "已成功从网络导入 \(count) 条净化规则"
        } catch {
            isDownloadingRules = false
            urlMessage = "下载失败：\(error.localizedDescription)"
        }
    }
}

private struct RuleHealthStats {
    let total: Int
    let enabled: Int
    let searchable: Int
    let readable: Int
    let problemSources: [BookSource]

    init(sources: [BookSource]) {
        total = sources.count
        enabled = sources.filter(\.enabled).count
        searchable = sources.filter { !($0.searchUrl?.isEmpty ?? true) }.count
        readable = sources.filter { $0.ruleContent != nil }.count
        problemSources = sources.filter {
            ($0.searchUrl?.isEmpty ?? true) || $0.ruleToc == nil || $0.ruleContent == nil
        }
    }
}

private struct AboutReadView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SourceReadSwift")
                        .font(.title2.bold())
                    Text("Swift 原生重写版。UI 继续对齐旧 Flutter 的 iOS 播客风格，核心书源兼容走新的 Swift-native 引擎。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("当前能力") {
                Label("书源 / 仓库 / RSS 分类导入", systemImage: "square.stack.3d.up")
                Label("发现页搜索、详情、目录、正文链路", systemImage: "magnifyingglass")
                Label("书架持久化、阅读进度、书签", systemImage: "books.vertical")
                Label("TXT 导入、自动分章、阅读设置持久化", systemImage: "doc.text")
            }

            Section("下一阶段") {
                Text("继续补 EPUB、RSS 阅读页、书源详情测试、规则编辑、阅读器朗读/自动翻页和更完整的 Flutter 功能迁移。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于阅读")
    }
}
