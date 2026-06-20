import SwiftUI
import UniformTypeIdentifiers

struct SourceManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var importText = ""
    @State private var importError: String?
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section("导入 JSON 书源") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("从文件导入 JSON", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    TextEditor(text: $importText)
                        .frame(minHeight: 140)
                        .font(.system(.body, design: .monospaced))

                    Button("导入") {
                        importSources()
                    }
                    .buttonStyle(.borderedProminent)

                    if let importError {
                        Text(importError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section("已导入 \(appState.sourceStore.sources.count) 个源") {
                    ForEach(appState.sourceStore.sources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.bookSourceName)
                                .font(.headline)
                            Text(source.bookSourceUrl)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let group = source.bookSourceGroup {
                                Text(group)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            appState.sourceStore.remove(appState.sourceStore.sources[index])
                        }
                    }
                    if let lastError = appState.sourceStore.lastError {
                        Text(lastError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("书源")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
            .task {
                appState.sourceStore.seedForDevelopment()
            }
        }
    }

    private func importSources() {
        do {
            try appState.sourceStore.importJSON(importText)
            importText = ""
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "无法访问所选文件"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let text = try String(contentsOf: url, encoding: .utf8)
            try appState.sourceStore.importJSON(text)
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }
}
