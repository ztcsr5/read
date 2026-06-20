import SwiftUI

struct SourceManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var importText = ""
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("导入 JSON 书源") {
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
                }
            }
            .navigationTitle("书源")
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
}

