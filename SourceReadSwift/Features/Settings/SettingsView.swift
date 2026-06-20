import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("原生重写状态") {
                    LabeledContent("UI", value: "SwiftUI")
                    LabeledContent("核心", value: "LegadoCore V2")
                    LabeledContent("书源范围", value: "小说")
                }

                Section("最近诊断") {
                    if appState.diagnostics.isEmpty {
                        Text("暂无诊断")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.diagnostics) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("[\(event.stage)] \(event.message)")
                                    .font(.subheadline.weight(.semibold))
                                if let sourceName = event.sourceName {
                                    Text(sourceName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("设置")
        }
    }
}

