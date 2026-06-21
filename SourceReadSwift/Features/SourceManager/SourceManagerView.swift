import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SourceManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var importText = ""
    @State private var importURL = ""
    @State private var importError: String?
    @State private var importMessage: String?
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PodcastSectionTitle(title: "书源管理", subtitle: "粘贴、文件或 URL 导入阅读书源")
                    importCard
                    sourceListCard
                }
                .padding(AppTheme.pagePadding)
            }
            .pageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
        }
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入书源")
                .font(.title2.bold())

            HStack {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("文件", systemImage: "doc.badge.plus")
                }
            }
            .buttonStyle(.borderedProminent)

            TextField("书源 JSON URL，可选", text: $importURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await importFromURL() }
            } label: {
                Label("从 URL 导入", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .disabled(importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            TextEditor(text: $importText)
                .frame(minHeight: 180)
                .font(.system(.body, design: .monospaced))
                .overlay {
                    if importText.isEmpty {
                        Text("粘贴 Legado/阅读书源 JSON")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                importSources()
            } label: {
                Label("导入文本", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
        }
        .podcastCard()
    }

    private var sourceListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已导入 \(appState.sourceStore.sources.count) 个源")
                .font(.title2.bold())

            if appState.sourceStore.sources.isEmpty {
                EmptyStateCard(systemImage: "tray", title: "暂无书源", message: "先导入书源 JSON，再去发现页搜索。")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(appState.sourceStore.sources) { source in
                        sourceRow(source)
                    }
                }
            }

            if let lastError = appState.sourceStore.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .podcastCard()
    }

    private func sourceRow(_ source: BookSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.bookSourceName)
                .font(.headline)
            Text(source.bookSourceUrl)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let group = source.bookSourceGroup {
                Text(group)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button(role: .destructive) {
                appState.sourceStore.remove(source)
            } label: {
                Label("删除", systemImage: "trash")
            }
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
